using Azure;
using Azure.Data.Tables;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;

namespace CIPP.TableClient;

/// <summary>
/// Dependency-free entry point over the vendored AzBobbyTables-derived table client,
/// used by CIPP's C# test engine to read <c>CippReportingDB</c> cache rows and write
/// <c>CippTestResults</c>.
///
/// The public surface deliberately exposes only BCL types (strings, dictionaries): the
/// <c>Azure.Data.Tables</c> types (<see cref="TableEntity"/> etc.) stay encapsulated so
/// that <c>CIPPSharp</c> — which project-references this assembly and owns the
/// <c>CIPP.Tests.ITableClient</c> contract — never needs the Azure SDK at compile time.
/// The two methods match <c>ITableClient</c>'s signatures so CIPPSharp can wrap an
/// instance of this class in a one-line adapter.
///
/// Connection resolution reads <c>$env:AzureWebJobsStorage</c> (the same connection
/// string every PowerShell table helper uses; works with Azurite for local dev). When
/// that is absent it falls back to a managed-identity token against
/// <c>$env:AzureWebJobsStorage__accountName</c>. A fresh service is created per call so
/// each call targets its own table; the underlying <see cref="System.Net.Http.HttpClient"/>
/// is shared and pooled across all of them by <see cref="AzDataTableService"/>.
/// </summary>
public sealed class VendoredTableClient
{
    /// <summary>The column on a CippReportingDB row that holds the record's JSON.</summary>
    private const string DataColumn = "Data";

    /// <summary>
    /// Read every logical row for a partition (optionally scoped to a RowKey prefix),
    /// reassembling entities the large-entity write path split across rows/properties,
    /// and return each row's <c>Data</c> column value as a raw JSON string.
    /// </summary>
    /// <remarks>
    /// The filter mirrors <c>New-CIPPDbRequest</c> exactly: for a typed read the caller
    /// passes <paramref name="rowKeyPrefix"/> as <c>"{Type}-"</c> and the exclusive upper
    /// bound is the prefix with its last character incremented (<c>"Users-"</c> →
    /// <c>"Users."</c>), i.e. <c>RowKey ge 'Users-' and RowKey lt 'Users.'</c>. An empty
    /// prefix reads the whole partition. Rows with no non-empty <c>Data</c> string (such
    /// as the <c>{Type}-Count</c> bookkeeping row, which stores <c>DataCount</c>) are
    /// skipped. A missing table yields an empty result rather than throwing.
    /// </remarks>
    /// <param name="table">The table name, e.g. <c>CippReportingDB</c>.</param>
    /// <param name="partitionKey">The partition key (tenant default domain).</param>
    /// <param name="rowKeyPrefix">RowKey prefix to scope to, or null/empty for the whole partition.</param>
    /// <returns>The <c>Data</c> JSON string of each matching logical row.</returns>
    public IReadOnlyList<string> ReadRows(string table, string partitionKey, string rowKeyPrefix)
    {
        if (string.IsNullOrEmpty(table))
        {
            throw new ArgumentException("Table name is required.", nameof(table));
        }
        if (string.IsNullOrEmpty(partitionKey))
        {
            throw new ArgumentException("PartitionKey is required.", nameof(partitionKey));
        }

        var filter = BuildPartitionPrefixFilter(partitionKey, rowKeyPrefix);

        AzDataTableService service;
        try
        {
            service = Connect(table, createIfNotExists: false);
        }
        catch (AzDataTableException ex) when (IsTableNotFound(ex))
        {
            return Array.Empty<string>();
        }

        IEnumerable<TableEntity> rows;
        try
        {
            rows = service.GetLargeEntitiesFromTable(filter);
        }
        catch (AzDataTableException ex) when (IsTableNotFound(ex))
        {
            return Array.Empty<string>();
        }

        var results = new List<string>();
        foreach (var row in rows)
        {
            if (row.TryGetValue(DataColumn, out var value) && value is string json && !string.IsNullOrWhiteSpace(json))
            {
                results.Add(json);
            }
        }
        return results;
    }

    /// <summary>
    /// Write result entities, transparently splitting any that exceed the table service
    /// size limits into AzBobbyTables-format part rows (<c>PartIndex</c>/<c>PartCount</c>/
    /// <c>OriginalEntityId</c> + <c>SplitOverProps</c> column chunks) and cleaning up
    /// stale part rows from earlier, larger versions.
    /// </summary>
    /// <remarks>
    /// Semantics match <c>Add-CIPPAzDataTableEntity -Force</c>, which upserts with
    /// <c>UpsertReplace</c> (verified against the AzBobbyTables cmdlet: <c>-Force</c> sets
    /// <c>OperationType = "UpsertReplace"</c>). Each dictionary must carry
    /// <c>PartitionKey</c> and <c>RowKey</c>; null-valued properties are dropped because
    /// the table service cannot store them. The table is created if it does not exist.
    /// </remarks>
    /// <param name="table">The table name, e.g. <c>CippTestResults</c>.</param>
    /// <param name="entities">The entities to write, each a property bag.</param>
    public void WriteEntities(string table, IEnumerable<IDictionary<string, object>> entities)
    {
        if (string.IsNullOrEmpty(table))
        {
            throw new ArgumentException("Table name is required.", nameof(table));
        }
        if (entities is null)
        {
            return;
        }

        var tableEntities = new List<TableEntity>();
        foreach (var entity in entities)
        {
            if (entity is null || entity.Count == 0)
            {
                continue;
            }
            tableEntities.Add(ToTableEntity(entity));
        }

        if (tableEntities.Count == 0)
        {
            return;
        }

        var service = Connect(table, createIfNotExists: true);
        // UpsertReplace == Add-CIPPAzDataTableEntity -Force.
        service.AddLargeEntitiesToTable(tableEntities, OperationTypeEnum.UpsertReplace);
    }

    /// <summary>
    /// Convert a plain property bag into a <see cref="TableEntity"/>, dropping null
    /// values (the service rejects them) and requiring the two key properties.
    /// </summary>
    private static TableEntity ToTableEntity(IDictionary<string, object> source)
    {
        var entity = new TableEntity();
        foreach (var pair in source)
        {
            if (pair.Value is null)
            {
                continue;
            }
            entity[pair.Key] = pair.Value;
        }

        if (!entity.ContainsKey("PartitionKey") || !entity.ContainsKey("RowKey"))
        {
            throw new ArgumentException("Each entity must carry non-null PartitionKey and RowKey properties.");
        }

        return entity;
    }

    /// <summary>
    /// Build the OData filter for a partition, optionally scoped to a RowKey prefix. The
    /// exclusive upper bound is the prefix with its last character incremented, matching
    /// New-CIPPDbRequest's <c>RowKey ge '{prefix}' and RowKey lt '{prefix+1}'</c>.
    /// </summary>
    private static string BuildPartitionPrefixFilter(string partitionKey, string? rowKeyPrefix)
    {
        var partitionClause = $"PartitionKey eq '{EscapeODataValue(partitionKey)}'";
        if (string.IsNullOrEmpty(rowKeyPrefix))
        {
            return partitionClause;
        }
        return $"{partitionClause} and {BuildRowKeyPrefixClause(rowKeyPrefix)}";
    }

    /// <summary>
    /// An OData clause matching every RowKey beginning with <paramref name="prefix"/>:
    /// <c>RowKey ge '{prefix}' and RowKey lt '{prefix with last char incremented}'</c>.
    /// </summary>
    private static string BuildRowKeyPrefixClause(string prefix)
    {
        var lower = $"RowKey ge '{EscapeODataValue(prefix)}'";

        var bound = prefix.ToCharArray();
        for (var i = bound.Length - 1; i >= 0; i--)
        {
            if (bound[i] < char.MaxValue)
            {
                bound[i]++;
                var upper = new string(bound, 0, i + 1);
                return $"({lower} and RowKey lt '{EscapeODataValue(upper)}')";
            }
        }

        // Every character is already the maximum, so nothing sorts above the prefix.
        return $"({lower})";
    }

    private static string EscapeODataValue(string value) => value.Replace("'", "''");

    /// <summary>
    /// Create a table service bound to <paramref name="table"/> using the storage
    /// connection string in <c>$env:AzureWebJobsStorage</c>, or a managed-identity token
    /// when no connection string is set.
    /// </summary>
    private static AzDataTableService Connect(string table, bool createIfNotExists)
    {
        var connectionString = Environment.GetEnvironmentVariable("AzureWebJobsStorage");
        if (!string.IsNullOrWhiteSpace(connectionString))
        {
            return AzDataTableService.CreateWithConnectionString(connectionString, table, createIfNotExists, CancellationToken.None);
        }

        // Identity-based connection (dual-stack Functions / App Service): resolve the
        // storage account and mint a managed-identity token for the Table service.
        var accountName = Environment.GetEnvironmentVariable("AzureWebJobsStorage__accountName");
        if (string.IsNullOrWhiteSpace(accountName))
        {
            throw new InvalidOperationException(
                "No storage connection available: set AzureWebJobsStorage (connection string) or AzureWebJobsStorage__accountName (managed identity).");
        }

        var clientId = Environment.GetEnvironmentVariable("AzureWebJobsStorage__clientId");
        var token = Helpers.GetManagedIdentityToken(accountName, clientId);
        return AzDataTableService.CreateWithToken(accountName, table, token, createIfNotExists, CancellationToken.None);
    }

    /// <summary>
    /// Whether the failure is a "table does not exist" error, which a read treats as an
    /// empty result rather than an error.
    /// </summary>
    private static bool IsTableNotFound(AzDataTableException ex)
    {
        for (Exception? inner = ex.InnerException; inner is not null; inner = inner.InnerException)
        {
            if (inner is RequestFailedException rfe &&
                (rfe.Status == 404 || string.Equals(rfe.ErrorCode, "TableNotFound", StringComparison.OrdinalIgnoreCase)))
            {
                return true;
            }
        }
        return false;
    }
}
