using Azure;
using Azure.Data.Tables;
using System;
using System.Collections;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using Azure.Core;
using Azure.Core.Pipeline;
using System.Net.Http;

namespace CIPP.TableClient;

/// <summary>
/// An internal representation of the TableTransactionActionType enum.
/// </summary>
public enum OperationTypeEnum
{
    Add,
    Delete,
    UpdateMerge,
    UpdateReplace,
    UpsertMerge,
    UpsertReplace
}

public class AzDataTableService
{
    private static readonly object _lock = new object();
    private static int _maxConnectionsPerServer = 0;
    private static HttpClient? _sharedHttpClient;
    private static HttpClientTransport? _sharedTransport;

    /// <summary>
    /// Shared HttpClient used by all TableClient/TableServiceClient instances.
    /// Connection pooling is handled by the runtime's SocketsHttpHandler (.NET Core 3.1+).
    /// This eliminates per-cmdlet TCP connection creation.
    /// </summary>
    private static HttpClient SharedHttpClient
    {
        get
        {
            if (_sharedHttpClient == null)
            {
                lock (_lock)
                {
                    if (_sharedHttpClient == null)
                    {
                        var handler = new HttpClientHandler();
                        if (_maxConnectionsPerServer > 0)
                        {
                            handler.MaxConnectionsPerServer = _maxConnectionsPerServer;
                        }
                        _sharedHttpClient = new HttpClient(handler);
                        _sharedTransport = new HttpClientTransport(_sharedHttpClient);
                    }
                }
            }
            return _sharedHttpClient;
        }
    }

    private static HttpClientTransport SharedTransport
    {
        get
        {
            _ = SharedHttpClient;
            return _sharedTransport!;
        }
    }

    /// <summary>
    /// Configures the maximum number of connections per server for the shared HTTP client.
    /// Must be called before any table operations. First call wins; subsequent calls are
    /// ignored once the HttpClient has been created.
    /// </summary>
    /// <param name="maxConnections">Maximum concurrent connections per server endpoint.</param>
    public static void ConfigureMaxConnectionsPerServer(int maxConnections)
    {
        if (_sharedHttpClient != null) return;
        lock (_lock)
        {
            if (_sharedHttpClient != null) return;
            _maxConnectionsPerServer = maxConnections;
        }
    }

    private static TableClientOptions CreateSharedOptions(int maxRetries)
    {
        var options = new TableClientOptions();
        options.Transport = SharedTransport;

        if (maxRetries > 0)
        {
            options.Retry.Mode = RetryMode.Fixed;
            options.Retry.Delay = TimeSpan.FromSeconds(1);
            options.Retry.MaxDelay = TimeSpan.FromSeconds(10);
            options.Retry.MaxRetries = maxRetries;
        }
        else
        {
            options.Retry.MaxRetries = 0;
        }

        return options;
    }

    /// <summary>
    /// The maximum number of entities Azure Table Storage accepts in a single transaction.
    /// </summary>
    private const int MaxTransactionSize = 100;

    /// <summary>
    /// The maximum page size Azure Table Storage accepts. A larger value is rejected with
    /// 400 InvalidInput rather than being capped, so any page size hint must be clamped to it.
    /// </summary>
    public const int MaxEntitiesPerPage = 1000;

    /// <summary>
    /// Calculates the page size to request for a query, or null to accept the service default.
    /// </summary>
    /// <remarks>
    /// Only a hint: it sizes each page, it does not limit the total. The caller still applies
    /// Take, and the SDK pages through transparently when more than one page is needed.
    /// Returns null when sorting, because ordering has to see every entity.
    /// The result is clamped to <see cref="MaxEntitiesPerPage"/> because the service rejects a
    /// larger page size outright with 400 InvalidInput instead of capping it. Note that Azurite
    /// does not enforce that limit, so only a direct assertion on this value catches a regression.
    /// </remarks>
    /// <param name="top">Maximum number of entities the caller asked for.</param>
    /// <param name="skip">Number of entities to skip; applied client side, so the page must cover them.</param>
    /// <param name="orderBy">Properties to sort by, if any.</param>
    /// <returns>The page size to request, or null for the service default.</returns>
    public static int? CalculatePageSize(int? top, int? skip, string[] orderBy)
    {
        if (!(top > 0) || (orderBy is not null && orderBy.Length > 0))
        {
            return null;
        }

        var skipped = skip > 0 ? skip.Value : 0;
        var needed = (long)skipped + top.Value;

        return (int)Math.Min(needed, MaxEntitiesPerPage);
    }

    /// <summary>
    /// Creates the transaction list, presized when the source count is known to avoid regrowing it.
    /// </summary>
    private static List<TableTransactionAction> CreateTransactionList(IEnumerable<TableEntity> entities) =>
        entities is ICollection<TableEntity> collection
            ? new List<TableTransactionAction>(collection.Count)
            : new List<TableTransactionAction>();

    private Azure.Data.Tables.TableClient? TableClient { get; set; }
    private TableServiceClient? TableServiceClient { get; set; }

    /// <summary>
    /// Cancellation token used within the AzDataTableService.
    /// </summary>
    private CancellationToken CancellationToken { get; }

    /// <summary>
    /// List of supported data types for the table.
    /// </summary>
    public static string[] SupportedTypeList { get; } = {
        "byte[]",
        "bool",
        "boolean",
        "datetime",
        "datetimeoffset",
        "double",
        "guid",
        "int32",
        "int",
        "int64",
        "long",
        "string"
    };

    private AzDataTableService(CancellationToken cancellationToken)
    {
        CancellationToken = cancellationToken;
    }

    private TableTransactionActionType ConvertOperationType(OperationTypeEnum operationType) =>
        Enum.TryParse(operationType.ToString(), out TableTransactionActionType transactionType)
            ? transactionType
            : throw new ArgumentException($"Invalid operation type: {operationType}");

    private static void CreateIfNotExists(Azure.Data.Tables.TableClient client, CancellationToken cancellationToken)
    {
        try
        {
            client.CreateIfNotExists(cancellationToken);
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("CreateTableError", ex);
        }
    }

    public static AzDataTableService CreateWithConnectionString(string connectionString, string tableName, bool createIfNotExists, CancellationToken cancellationToken, int maxRetries = 0)
    {
        try
        {
            var dataTableService = new AzDataTableService(cancellationToken);

            TableServiceClient serviceClient = new(connectionString, CreateSharedOptions(maxRetries));

            if (tableName is not null)
            {
                Azure.Data.Tables.TableClient client = new(connectionString, tableName, CreateSharedOptions(maxRetries));

                if (createIfNotExists && !string.IsNullOrWhiteSpace(tableName))
                {
                    CreateIfNotExists(client, cancellationToken);
                }

                dataTableService.TableClient = client;
            }

            dataTableService.TableServiceClient = serviceClient;
            return dataTableService;
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("ConnectWithConnectionStringError", ex);
        }
    }

    public static AzDataTableService CreateWithStorageKey(string storageAccountName, string tableName, string storageAccountKey, bool createIfNotExists, CancellationToken cancellationToken, int maxRetries = 0)
    {
        try
        {
            var dataTableService = new AzDataTableService(cancellationToken);
            var tableEndpoint = new Uri($"https://{storageAccountName}.table.core.windows.net/{tableName}");

            var sasCredential = new TableSharedKeyCredential(storageAccountName, storageAccountKey);

            TableServiceClient serviceClient = new(tableEndpoint, sasCredential, CreateSharedOptions(maxRetries));

            if (tableName is not null)
            {
                Azure.Data.Tables.TableClient client = new(tableEndpoint, tableName, sasCredential, CreateSharedOptions(maxRetries));

                if (createIfNotExists && !string.IsNullOrWhiteSpace(tableName))
                {
                    CreateIfNotExists(client, cancellationToken);
                }

                dataTableService.TableClient = client;
            }

            dataTableService.TableServiceClient = serviceClient;
            return dataTableService;
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("ConnectWithStorageKeyError", ex);
        }
    }

    public static AzDataTableService CreateWithToken(string storageAccountName, string tableName, string token, bool createIfNotExists, CancellationToken cancellationToken, int maxRetries = 0)
    {
        try
        {
            var dataTableService = new AzDataTableService(cancellationToken);
            var tableEndpoint = new Uri($"https://{storageAccountName}.table.core.windows.net/{tableName}");

            TableServiceClient serviceClient = new(tableEndpoint, new ExternalTokenCredential(token, DateTimeOffset.Now.Add(TimeSpan.FromHours(1))), CreateSharedOptions(maxRetries));

            if (tableName is not null)
            {
                Azure.Data.Tables.TableClient client = new(tableEndpoint, tableName, new ExternalTokenCredential(token, DateTimeOffset.Now.Add(TimeSpan.FromHours(1))), CreateSharedOptions(maxRetries));

                if (createIfNotExists && !string.IsNullOrWhiteSpace(tableName))
                {
                    CreateIfNotExists(client, cancellationToken);
                }

                dataTableService.TableClient = client;
            }
            dataTableService.TableServiceClient = serviceClient;
            return dataTableService;
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("ConnectWithTokenError", ex);
        }
    }

    public static AzDataTableService CreateWithSAS(Uri sasUrl, string tableName, bool createIfNotExists, CancellationToken cancellationToken, int maxRetries = 0)
    {
        try
        {
            var dataTableService = new AzDataTableService(cancellationToken);
            // The credential is built only using the token
            var sasCredential = new AzureSasCredential(sasUrl.Query);

            // Extract the base URL (without the table name)
            var baseUrl = new Uri(sasUrl.GetLeftPart(UriPartial.Authority));

            // If the user did not specify a full endpoint to the table
            if (!sasUrl.ToString().Contains($"/{tableName}?"))
            {
                // Insert the table name before the URL parameters
                var urlParts = sasUrl.ToString().Split('?');
                sasUrl = new Uri($"{urlParts.First().TrimEnd('/')}/{tableName}?{urlParts.Last()}");
            }

            TableServiceClient serviceClient = new TableServiceClient(baseUrl, sasCredential, CreateSharedOptions(maxRetries));
            if (tableName is not null)
            {
                Azure.Data.Tables.TableClient client = new(sasUrl, sasCredential, CreateSharedOptions(maxRetries));

                if (createIfNotExists && !string.IsNullOrWhiteSpace(tableName))
                {
                    CreateIfNotExists(client, cancellationToken);
                }

                dataTableService.TableClient = client;
            }
            dataTableService.TableServiceClient = serviceClient;
            return dataTableService;
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("ConnectWithSASError", ex);
        }
    }

    /// <summary>
    /// Get a list of tables from the storage account.
    /// </summary>
    /// <param name="filter">The filter string to use in the query.</param>
    /// <returns>The list of tables as strings.</returns>
    public IEnumerable<string> GetTables(string filter)
    {
        try
        {
            var tables = TableServiceClient!.Query(filter, null, CancellationToken);
            // Return Name property of each table
            return tables.Select(t => t.Name);
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("GetTablesError", ex);
        }
    }

    /// <summary>
    /// Remove a table from the storage account.
    /// </summary>
    public void RemoveTable()
    {
        ValidateTableClient();

        try
        {
            TableClient?.Delete();
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("DeleteTableError", ex);
        }
    }

    /// <summary>
    /// Add one or more entities to a table.
    /// </summary>
    /// <param name="entities">The entities to add.</param>
    /// <param name="operationType">The type of operation to perform.</param>
    public void AddEntitiesToTable(IEnumerable<TableEntity> entities, OperationTypeEnum operationType)
    {
        ValidateTableClient();

        try
        {
            var transactions = CreateTransactionList(entities);

            var tableEntities = entities.Select(ValidateTableEntity);

            var transactionType = ConvertOperationType(operationType);
            transactions.AddRange(tableEntities.Select(e => new TableTransactionAction(transactionType, e)));

            SubmitTransaction(transactions);
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("AddEntitiesError", ex);
        }
    }

    /// <summary>
    /// Remove one or more entities from a table.
    /// </summary>
    /// <param name="entities">The entities to remove.</param>
    /// <param name="validateEtag">Whether or not to validate that the ETag is the same and the item has not changed.</param>
    public void RemoveEntitiesFromTable(IEnumerable<TableEntity> entities, bool validateEtag = true)
    {
        ValidateTableClient();

        try
        {
            var transactions = CreateTransactionList(entities);

            var tableEntities = entities.Select(ValidateTableEntity);

            transactions.AddRange(tableEntities.Select(e => new TableTransactionAction(TableTransactionActionType.Delete, e, validateEtag ? e.ETag : default)));

            SubmitTransaction(transactions);
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("RemoveEntitiesError", ex);
        }
    }

    /// <summary>
    /// Update one or more entities in a table.
    /// </summary>
    /// <param name="entities">The entities to update.</param>
    /// <param name="operationType">The type of operation to perform.</param>
    /// <param name="validateEtag">Whether or not to validate that the ETag is the same and the item has not changed.</param>
    public void UpdateEntitiesInTable(IEnumerable<TableEntity> entities, OperationTypeEnum operationType, bool validateEtag = true)
    {
        ValidateTableClient();

        if (operationType is not (OperationTypeEnum.UpdateMerge or OperationTypeEnum.UpdateReplace))
        {
            throw new ArgumentException($"Operation type {operationType} is not valid for updates of entities, use UpdateMerge or UpdateReplace!");
        }

        try
        {
            var transactions = CreateTransactionList(entities);

            var tableEntities = entities.Select(ValidateTableEntity);

            var transactionType = ConvertOperationType(operationType);

            // Update actions must always carry If-Match; with a default ETag the
            // service treats a batched merge or replace as an upsert and silently
            // creates missing rows. ETag.All matches the non-batched path.
            transactions.AddRange(tableEntities.Select(e =>
            {
                var etag = validateEtag && e.ETag != default ? e.ETag : ETag.All;
                return new TableTransactionAction(transactionType, e, etag);
            }));

            SubmitTransaction(transactions);
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("UpdateEntitiesError", ex);
        }
    }

    /// <summary>
    /// Get entities from a table based on a OData query.
    /// </summary>
    /// <param name="query">The query to filter entities by.</param>
    /// <returns>The result of the query.</returns>
    public IEnumerable<TableEntity> GetEntitiesFromTable(string query, string[] properties = null!, int? top = null, int? skip = null, string[] orderBy = null!)
    {
        ValidateTableClient();

        try
        {
            // When the caller wants a bounded number of entities and no sorting is needed, ask the
            // service for only that many per page. Otherwise the first page returns up to 1000
            // entities and everything past the requested count is fetched and then discarded.
            var maxPerPage = CalculatePageSize(top, skip, orderBy);

            // Declare type as IEnumerable to be able to overwrite it with LINQ results further down.
            // Query rather than QueryAsync: the result is handed back to PowerShell synchronously either way
            IEnumerable<TableEntity> entities = TableClient!.Query<TableEntity>(query, maxPerPage, properties, CancellationToken);

            // If user specified one or more properties to sort list by
            // This may slow the query down a lot with a lot of results
            if (orderBy is not null && orderBy.Any())
            {
                // Must create a new variable to be able to modify it within the loop
                // OrderBy for the first property, ThenBy for the rest
                var orderableEntities = entities.OrderBy(e => e[orderBy.First()]);
                foreach (var propertyName in orderBy.Skip(1))
                {
                    orderableEntities = orderableEntities.ThenBy(e => e[propertyName]);
                }
                entities = orderableEntities;
            }
            // If user specified to skip a number of entities
            if (skip is not null)
            {
                entities = entities.Skip((int)skip);
            }
            // If user asked to only take a number of entities
            if (top is not null)
            {
                entities = entities.Take((int)top);
            }

            // Materialize so any query failure surfaces here (inside the try), and the
            // caller receives concrete TableEntity instances.
            return entities.ToList();
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("GetEntitiesError", ex);
        }
    }

    /// <summary>
    /// Count the entities in a table matching a query.
    /// </summary>
    /// <param name="query">The query to filter entities by.</param>
    /// <returns>The number of matching entities.</returns>
    public int CountEntitiesInTable(string query)
    {
        ValidateTableClient();

        try
        {
            // Only the keys are requested, and the entities are counted without being
            // materialized further, since the caller only wants the total.
            var entities = TableClient!.Query<TableEntity>(query, null, ["PartitionKey", "RowKey"], CancellationToken);

            var count = 0;
            foreach (var _ in entities)
            {
                count++;
            }

            return count;
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("GetEntitiesError", ex);
        }
    }

    /// <summary>
    /// Clear all entities from a table.
    /// </summary>
    public void ClearTable()
    {
        ValidateTableClient();

        try
        {
            var entities = TableClient!.Query<TableEntity>((string)null!, null, ["PartitionKey", "RowKey"]);

            var transactions = new List<TableTransactionAction>();

            transactions.AddRange(entities.Select(e => new TableTransactionAction(TableTransactionActionType.Delete, e)));

            SubmitTransaction(transactions);
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("ClearTableError", ex);
        }
    }

    /// <summary>
    /// Submit transactions with built-in batch handling and splitting of partitions.
    /// </summary>
    private void SubmitTransaction(IList<TableTransactionAction> transactions)
    {
        ValidateTableClient();

        // Transactions only support up to 100 entities of the same partitionkey
        // Loop through transactions grouped by partitionkey
        foreach (var group in transactions.GroupBy(t => t.Entity.PartitionKey))
        {
            // Loop through each group and submit up to 100 at a time
            var count = group.Count();
            for (int i = 0; i < count; i += MaxTransactionSize)
            {
                TableClient!.SubmitTransaction(group.Skip(i).Take(MaxTransactionSize), CancellationToken);
            }
        }
    }

    /// <summary>
    /// Validate that the TableName is set in the context.
    /// </summary>
    private void ValidateTableClient()
    {
        if (TableClient is null)
        {
            throw new AzDataTableException("TableClientError", new InvalidOperationException("Table name is not set in the TableContext, please create a new context for this operation!"));
        }
    }

    #region Large entity operations

    /// <summary>
    /// Properties to request when only the row identity is needed.
    /// </summary>
    private static readonly string[] KeysOnlyProperties = { "PartitionKey", "RowKey" };

    /// <summary>
    /// Number of RowKeys to combine into one OData filter when looking up part rows.
    /// </summary>
    private const int PartLookupChunkSize = 10;

    /// <summary>
    /// Add one or more entities to a table, transparently splitting entities that
    /// exceed the Azure Table Storage size limits across multiple properties and rows.
    /// See <see cref="EntitySplitter"/> for the storage format.
    ///
    /// Entities are deduplicated by PartitionKey and RowKey (the last occurrence wins)
    /// so one call can safely carry several versions of the same logical entity, and
    /// leftover part rows from earlier, larger versions of a split entity are removed
    /// after a successful write.
    /// </summary>
    /// <param name="entities">The entities to add (can be any supported type).</param>
    /// <param name="operationType">The type of operation to perform.</param>
    public void AddLargeEntitiesToTable(IEnumerable<TableEntity> entities, OperationTypeEnum operationType)
    {
        ValidateTableClient();

        try
        {
            var transactionType = ConvertOperationType(operationType);

            // Deduplicate by entity identity, last one wins. A transaction containing
            // two operations for the same key is rejected by the service outright.
            var order = new List<(string PartitionKey, string RowKey)>();
            var latest = new Dictionary<(string PartitionKey, string RowKey), TableEntity>();
            foreach (var entity in entities)
            {
                var tableEntity = ValidateTableEntity(entity);
                var key = (tableEntity.PartitionKey, tableEntity.RowKey);
                if (!latest.ContainsKey(key))
                {
                    order.Add(key);
                }
                latest[key] = tableEntity;
            }

            var actions = new List<TableTransactionAction>(order.Count);
            var splitEntities = new List<(string PartitionKey, string RowKey, HashSet<string> LiveRowKeys)>();

            foreach (var key in order)
            {
                var result = EntitySplitter.Split(latest[key]);

                if (!result.Engaged)
                {
                    actions.Add(new TableTransactionAction(transactionType, result.Rows[0]));
                    continue;
                }

                // Merging cannot remove properties from existing rows, and the
                // property distribution over rows is not stable between writes, so a
                // merged multi-row write would leave stale values behind on other rows
                // and corrupt the reassembled entity. Multi-row merges are therefore
                // promoted to full replacement.
                var rowActionType = result.Rows.Count > 1 && transactionType == TableTransactionActionType.UpsertMerge
                    ? TableTransactionActionType.UpsertReplace
                    : transactionType;

                foreach (var row in result.Rows)
                {
                    actions.Add(new TableTransactionAction(rowActionType, row));
                }

                splitEntities.Add((key.PartitionKey, key.RowKey, new HashSet<string>(result.Rows.Select(r => r.RowKey), StringComparer.Ordinal)));
            }

            SubmitTransactionSized(actions);

            // Remove leftover part rows from earlier writes that used more rows than
            // this one, so stale data cannot leak into reassembly.
            foreach (var (partitionKey, rowKey, liveRowKeys) in splitEntities)
            {
                RemoveStalePartRows(partitionKey, rowKey, liveRowKeys);
            }
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("AddLargeEntitiesError", ex);
        }
    }

    /// <summary>
    /// Get entities from a table based on an OData query, reassembling entities that
    /// were split across multiple properties or rows by the large-entity write path.
    /// See <see cref="EntitySplitter"/> for the storage format.
    ///
    /// Sorting, skipping and taking apply to the physical rows before reassembly, and
    /// property selection that excludes the split markers prevents reassembly, so
    /// filters should target the PartitionKey level when split entities are involved.
    /// </summary>
    /// <param name="query">The query to filter entities by.</param>
    /// <param name="properties">The list of properties to return.</param>
    /// <param name="top">The maximum number of physical rows to retrieve.</param>
    /// <param name="skip">The number of physical rows to skip.</param>
    /// <param name="orderBy">The names of one or more properties to sort by.</param>
    /// <param name="onWarning">Called with a message when a malformed split manifest, or an
    /// entity whose rows could not be reassembled, is skipped.</param>
    /// <returns>The reassembled entities.</returns>
    public IEnumerable<TableEntity> GetLargeEntitiesFromTable(string query, string[] properties = null!, int? top = null, int? skip = null, string[] orderBy = null!, Action<string> onWarning = null!)
    {
        ValidateTableClient();

        try
        {
            // Page size hint, same reasoning as GetEntitiesFromTable.
            var maxPerPage = CalculatePageSize(top, skip, orderBy);

            IEnumerable<TableEntity> entities = TableClient!.Query<TableEntity>(query, maxPerPage, properties, CancellationToken);

            if (orderBy is not null && orderBy.Any())
            {
                var orderableEntities = entities.OrderBy(e => e[orderBy.First()]);
                foreach (var propertyName in orderBy.Skip(1))
                {
                    orderableEntities = orderableEntities.ThenBy(e => e[propertyName]);
                }
                entities = orderableEntities;
            }
            if (skip is not null)
            {
                entities = entities.Skip((int)skip);
            }
            if (top is not null)
            {
                entities = entities.Take((int)top);
            }

            // Reassembly needs the whole result set: part rows carry no ordering
            // guarantee relative to their siblings once sorting or filters apply, and a
            // caller's filter has no reason to match the rows an entity was split over.
            var rows = RecoverMissingPartRows(entities.ToList(), properties);

            // An entity that cannot be reassembled is reported and left out rather than failing the
            // query: missing rows are a property of that entity alone, and the others returned by
            // the same filter are unaffected by it. Both the malformed-manifest warning and the
            // incomplete-entity report are surfaced through onWarning.
            return EntitySplitter.Reassemble(
                    rows,
                    onWarning,
                    incomplete => onWarning?.Invoke(incomplete.Message))
                .ToList();
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("GetLargeEntitiesError", ex);
        }
    }

    /// <summary>
    /// Lazy equivalent of <see cref="GetLargeEntitiesFromTable"/> for the read path: plain
    /// (non-split) rows are yielded as they page in, so the whole result set is never materialised;
    /// only split-part rows (those carrying <see cref="EntitySplitter.OriginalEntityIdKey"/>, which
    /// are rare) are buffered and reassembled at the end via the same recover+reassemble logic. A
    /// plain row supersedes leftover parts of the same identity, so a reassembled group whose identity
    /// a plain row already emitted is dropped — matching Reassemble's plain-precedence rule. No
    /// ordering/skip/top/orderBy support (the read path does not use them).
    /// </summary>
    public IEnumerable<TableEntity> StreamLargeEntitiesFromTable(string query, string[] properties = null!, Action<string> onWarning = null!)
    {
        ValidateTableClient();

        var maxPerPage = CalculatePageSize(null, null, null!);
        IEnumerator<TableEntity> src;
        try
        {
            src = TableClient!.Query<TableEntity>(query, maxPerPage, properties, CancellationToken).GetEnumerator();
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("GetLargeEntitiesError", ex);
        }

        var plainKeys = new HashSet<(string, string)>();
        var parts = new List<TableEntity>();
        using (src)
        {
            while (true)
            {
                TableEntity entity;
                var tableGone = false;
                try
                {
                    if (!src.MoveNext()) break;
                    entity = src.Current;
                }
                // A missing table surfaces here (pages are fetched lazily on MoveNext). Match the eager
                // path: treat it as an empty result rather than throwing.
                catch (RequestFailedException rfe) when (rfe.Status == 404 || string.Equals(rfe.ErrorCode, "TableNotFound", StringComparison.OrdinalIgnoreCase))
                {
                    tableGone = true;
                    entity = null!;
                }
                if (tableGone) yield break;

                // A row needs reassembly if it is a cross-ROW split part (carries OriginalEntityId) OR
                // a cross-COLUMN chunked row (carries the SplitOverProps marker; its Data is spread
                // across Data/Data_1/... and must be rejoined). Only rows with neither marker are plain
                // and safe to stream as-is.
                if (entity.ContainsKey(EntitySplitter.OriginalEntityIdKey) ||
                    entity.ContainsKey(EntitySplitter.SplitOverPropsKey))
                {
                    parts.Add(entity); // split/chunked row: buffer for reassembly
                }
                else
                {
                    plainKeys.Add((entity.PartitionKey, entity.RowKey));
                    yield return entity;
                }
            }
        }

        if (parts.Count == 0)
        {
            yield break;
        }

        var recovered = RecoverMissingPartRows(parts, properties);
        foreach (var reassembled in EntitySplitter.Reassemble(recovered, onWarning, inc => onWarning?.Invoke(inc.Message)))
        {
            if (plainKeys.Contains((reassembled.PartitionKey, reassembled.RowKey))) continue; // plain wins
            yield return reassembled;
        }
    }

    /// <summary>
    /// Fetch the rows of any entity in <paramref name="rows"/> that is only partly
    /// present, and return the set with them added.
    /// </summary>
    /// <remarks>
    /// Part rows are named <c>{RowKey}-part{n}</c>, so they are matched by a RowKey
    /// range scoped to the entity's partition: an index seek, and no dependence on the
    /// stored type of any marker property.
    /// </remarks>
    /// <param name="rows">The rows returned by the caller's query.</param>
    /// <param name="properties">The property projection the caller asked for, if any.</param>
    private List<TableEntity> RecoverMissingPartRows(List<TableEntity> rows, string[] properties)
    {
        var incomplete = EntitySplitter.FindIncompleteGroups(rows);
        if (incomplete.Count == 0)
        {
            return rows;
        }

        // Rows the caller already matched are not added twice.
        var seen = new HashSet<(string PartitionKey, string RowKey)>(rows.Select(r => (r.PartitionKey, r.RowKey)));

        foreach (var partitionGroup in incomplete.GroupBy(g => g.PartitionKey, StringComparer.Ordinal))
        {
            var partitionClause = $"PartitionKey eq '{EscapeODataValue(partitionGroup.Key)}'";

            foreach (var entityId in partitionGroup.Select(g => g.EntityId).Distinct(StringComparer.Ordinal))
            {
                var filter = $"{partitionClause} and {BuildRowKeyPrefixClause(entityId)}";

                foreach (var row in TableClient!.Query<TableEntity>(filter, null, properties, CancellationToken))
                {
                    if (seen.Add((row.PartitionKey, row.RowKey)))
                    {
                        rows.Add(row);
                    }
                }
            }
        }

        return rows;
    }

    /// <summary>
    /// An OData clause matching every RowKey beginning with <paramref name="prefix"/>.
    /// </summary>
    /// <remarks>
    /// The upper bound is the prefix with its last character incremented: the smallest
    /// string sorting above every string that starts with it.
    /// </remarks>
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

    /// <summary>
    /// Remove one or more entities from a table, including any part rows the entities
    /// were split into by the large-entity write path. Part rows are looked up by the
    /// OriginalEntityId marker and removed unconditionally; ETag validation, when
    /// requested, applies to the entity's own row.
    /// </summary>
    /// <param name="entities">The entities to remove (can be any supported type).</param>
    /// <param name="validateEtag">Whether or not to validate that the ETag is the same and the item has not changed.</param>
    public void RemoveLargeEntitiesFromTable(IEnumerable<TableEntity> entities, bool validateEtag = true)
    {
        ValidateTableClient();

        try
        {
            var mainRows = entities.Select(ValidateTableEntity).ToList();
            var mainKeys = new HashSet<(string PartitionKey, string RowKey)>(mainRows.Select(e => (e.PartitionKey, e.RowKey)));

            var actions = new List<TableTransactionAction>(mainRows.Count);
            foreach (var entity in mainRows)
            {
                actions.Add(new TableTransactionAction(TableTransactionActionType.Delete, entity, validateEtag ? entity.ETag : default));
            }

            // Find the part rows belonging to the removed entities. OriginalEntityId
            // is matched in chunked OR filters to keep the number of queries low.
            foreach (var partitionGroup in mainRows.GroupBy(e => e.PartitionKey))
            {
                var rowKeys = partitionGroup.Select(e => e.RowKey).Distinct(StringComparer.Ordinal).ToList();
                for (var i = 0; i < rowKeys.Count; i += PartLookupChunkSize)
                {
                    var conditions = string.Join(" or ", rowKeys
                        .Skip(i)
                        .Take(PartLookupChunkSize)
                        .Select(rowKey => $"{EntitySplitter.OriginalEntityIdKey} eq '{EscapeODataValue(rowKey)}'"));
                    var filter = $"PartitionKey eq '{EscapeODataValue(partitionGroup.Key)}' and ({conditions})";

                    foreach (var partRow in TableClient!.Query<TableEntity>(filter, null, KeysOnlyProperties, CancellationToken))
                    {
                        if (!mainKeys.Contains((partRow.PartitionKey, partRow.RowKey)))
                        {
                            actions.Add(new TableTransactionAction(TableTransactionActionType.Delete, partRow));
                        }
                    }
                }
            }

            SubmitTransactionSized(actions);
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("RemoveLargeEntitiesError", ex);
        }
    }

    /// <summary>
    /// Update one or more entities that already exist in a table, transparently
    /// handling entities that were split across multiple properties or rows by the
    /// large-entity write path. See <see cref="EntitySplitter"/> for the storage
    /// format. Unlike <see cref="AddLargeEntitiesToTable"/> with an upsert operation
    /// type, entities that do not exist cause an error and are never created.
    ///
    /// UpdateReplace replaces the whole logical entity: the root row is updated (and
    /// fails if missing), part rows the new version needs are upserted, and part rows
    /// it no longer uses are removed.
    ///
    /// UpdateMerge merges the given properties into the logical entity. A plain
    /// single-row entity is merged in place; an entity that was split, or incoming
    /// properties that are themselves oversized, are read, merged in memory and
    /// rewritten, since merging onto physical rows directly would corrupt reassembly.
    ///
    /// ETag validation, when requested, applies to the entity's root row. The
    /// read-merge-rewrite path is not atomic.
    /// </summary>
    /// <param name="entities">The entities to update (can be any supported type).</param>
    /// <param name="operationType">The type of operation to perform, UpdateMerge or UpdateReplace.</param>
    /// <param name="validateEtag">Whether or not to validate that the ETag is the same and the item has not changed.</param>
    public void UpdateLargeEntitiesInTable(IEnumerable<TableEntity> entities, OperationTypeEnum operationType, bool validateEtag = true)
    {
        ValidateTableClient();

        try
        {
            if (operationType is not (OperationTypeEnum.UpdateMerge or OperationTypeEnum.UpdateReplace))
            {
                throw new ArgumentException($"Operation type {operationType} is not valid for updates of large entities, use UpdateMerge or UpdateReplace!");
            }

            // Deduplicate by entity identity, last one wins, same as the add path.
            var order = new List<(string PartitionKey, string RowKey)>();
            var latest = new Dictionary<(string PartitionKey, string RowKey), TableEntity>();
            foreach (var entity in entities)
            {
                var tableEntity = ValidateTableEntity(entity);
                var key = (tableEntity.PartitionKey, tableEntity.RowKey);
                if (!latest.ContainsKey(key))
                {
                    order.Add(key);
                }
                latest[key] = tableEntity;
            }

            // Updating requires existence, and the merge path needs the split markers
            // to decide whether merging onto the root row directly is safe.
            var storedRoots = FetchRootRows(order);

            var missing = order.Where(key => !storedRoots.ContainsKey(key)).ToList();
            if (missing.Count > 0)
            {
                var described = string.Join(", ", missing.Select(k => $"PartitionKey='{k.PartitionKey}' RowKey='{k.RowKey}'"));
                throw new InvalidOperationException($"Cannot update one or more entities because they do not exist: {described}");
            }

            var actions = new List<TableTransactionAction>(order.Count);
            var splitEntities = new List<(string PartitionKey, string RowKey, HashSet<string> LiveRowKeys)>();

            foreach (var key in order)
            {
                var incoming = latest[key];
                var storedRoot = storedRoots[key];
                // Update actions must always carry If-Match; with a default ETag the
                // service treats a batched merge or replace as an upsert.
                var etag = validateEtag && incoming.ETag != default ? incoming.ETag : ETag.All;
                var storedIsSplit = HasSplitMarkers(storedRoot);

                if (operationType == OperationTypeEnum.UpdateMerge)
                {
                    if (!storedIsSplit)
                    {
                        var incomingSplit = EntitySplitter.Split(incoming);
                        if (!incomingSplit.Engaged)
                        {
                            // Plain stored row, plain incoming properties: one merge.
                            actions.Add(new TableTransactionAction(TableTransactionActionType.UpdateMerge, incomingSplit.Rows[0], etag));
                            continue;
                        }
                        // Oversized incoming properties fall through to the
                        // read-merge-rewrite path so the stored properties survive.
                    }

                    var stored = ReadLogicalEntity(key.PartitionKey, key.RowKey);
                    var merged = new TableEntity(key.PartitionKey, key.RowKey);
                    foreach (var property in stored)
                    {
                        if (property.Key is "PartitionKey" or "RowKey" or "Timestamp" or "odata.etag" or "ETag")
                        {
                            continue;
                        }
                        merged[property.Key] = property.Value;
                    }
                    foreach (var property in incoming)
                    {
                        if (property.Key is "PartitionKey" or "RowKey" or "Timestamp" or "odata.etag" or "ETag")
                        {
                            continue;
                        }
                        merged[property.Key] = property.Value;
                    }
                    incoming = merged;
                }

                var result = EntitySplitter.Split(incoming);

                // Update rather than upsert the root row, so an entity deleted since
                // the existence check fails instead of being partially recreated.
                actions.Add(new TableTransactionAction(TableTransactionActionType.UpdateReplace, result.Rows[0], etag));
                foreach (var row in result.Rows.Skip(1))
                {
                    actions.Add(new TableTransactionAction(TableTransactionActionType.UpsertReplace, row));
                }

                if (result.Engaged || storedIsSplit)
                {
                    splitEntities.Add((key.PartitionKey, key.RowKey, new HashSet<string>(result.Rows.Select(r => r.RowKey), StringComparer.Ordinal)));
                }
            }

            SubmitTransactionSized(actions);

            // Remove leftover part rows from earlier writes that used more rows than
            // this one, so stale data cannot leak into reassembly.
            foreach (var (partitionKey, rowKey, liveRowKeys) in splitEntities)
            {
                RemoveStalePartRows(partitionKey, rowKey, liveRowKeys);
            }
        }
        catch (Exception ex)
        {
            throw new AzDataTableException("UpdateLargeEntitiesError", ex);
        }
    }

    /// <summary>
    /// Properties needed to classify a stored root row for the update path: the split
    /// markers, and the keys.
    /// </summary>
    private static readonly string[] RootMarkerProperties =
    {
        "PartitionKey",
        "RowKey",
        EntitySplitter.SplitOverPropsKey,
        EntitySplitter.PartCountKey,
        EntitySplitter.OriginalEntityIdKey,
    };

    /// <summary>
    /// Fetch the root rows for the given logical entity keys, selecting only the keys
    /// and split markers. RowKeys are matched in chunked OR filters to keep the number
    /// of queries low. Keys whose root row does not exist are absent from the result.
    /// </summary>
    private Dictionary<(string PartitionKey, string RowKey), TableEntity> FetchRootRows(List<(string PartitionKey, string RowKey)> keys)
    {
        var found = new Dictionary<(string PartitionKey, string RowKey), TableEntity>();

        foreach (var partitionGroup in keys.GroupBy(k => k.PartitionKey, StringComparer.Ordinal))
        {
            var rowKeys = partitionGroup.Select(k => k.RowKey).Distinct(StringComparer.Ordinal).ToList();
            for (var i = 0; i < rowKeys.Count; i += PartLookupChunkSize)
            {
                var conditions = string.Join(" or ", rowKeys
                    .Skip(i)
                    .Take(PartLookupChunkSize)
                    .Select(rowKey => $"RowKey eq '{EscapeODataValue(rowKey)}'"));
                var filter = $"PartitionKey eq '{EscapeODataValue(partitionGroup.Key)}' and ({conditions})";

                foreach (var row in TableClient!.Query<TableEntity>(filter, null, RootMarkerProperties, CancellationToken))
                {
                    found[(row.PartitionKey, row.RowKey)] = row;
                }
            }
        }

        return found;
    }

    /// <summary>
    /// Whether a root row carries any of the markers the large-entity write path
    /// stamps on split entities.
    /// </summary>
    private static bool HasSplitMarkers(TableEntity root) =>
        root.ContainsKey(EntitySplitter.SplitOverPropsKey) ||
        root.ContainsKey(EntitySplitter.PartCountKey) ||
        root.ContainsKey(EntitySplitter.OriginalEntityIdKey);

    /// <summary>
    /// Read one logical entity, reassembling it from its physical rows. Throws when
    /// the entity does not exist or its rows cannot be reassembled.
    /// </summary>
    private TableEntity ReadLogicalEntity(string partitionKey, string rowKey)
    {
        // The prefix range is an index seek that catches the root row and every
        // "{RowKey}-part{n}" row, but also unrelated rows sharing the prefix; filter
        // to rows that belong to this entity before reassembling.
        var filter = $"PartitionKey eq '{EscapeODataValue(partitionKey)}' and {BuildRowKeyPrefixClause(rowKey)}";
        var rows = TableClient!.Query<TableEntity>(filter, null, null, CancellationToken)
            .Where(row => row.RowKey == rowKey ||
                (row.TryGetValue(EntitySplitter.OriginalEntityIdKey, out var id) && id?.ToString() == rowKey))
            .ToList();

        IncompleteEntityException? incomplete = null;
        var entity = EntitySplitter.Reassemble(rows, null, ex => incomplete ??= ex)
            .FirstOrDefault(e => e.RowKey == rowKey);

        if (incomplete is not null)
        {
            throw incomplete;
        }

        return entity ?? throw new InvalidOperationException($"Cannot update entity with PartitionKey='{partitionKey}' and RowKey='{rowKey}' because it does not exist.");
    }

    /// <summary>
    /// Validate that an input entity carries the required keys, returning it unchanged.
    /// </summary>
    private static TableEntity ValidateTableEntity(TableEntity entity)
    {
        if (!entity.ContainsKey("PartitionKey") || !entity.ContainsKey("RowKey"))
        {
            throw new ArgumentException("Entity is missing required PartitionKey or RowKey properties!");
        }

        return entity;
    }

    /// <summary>
    /// Submit transactions grouped by partition, packing each batch by count and by
    /// estimated payload size. Rows produced by entity splitting approach the row
    /// budget individually, so packing 100 of them into one transaction would exceed
    /// the service's batch payload limit.
    /// </summary>
    private void SubmitTransactionSized(IList<TableTransactionAction> transactions)
    {
        foreach (var group in transactions.GroupBy(t => t.Entity.PartitionKey))
        {
            var batch = new List<TableTransactionAction>();
            long batchSize = 0;

            foreach (var action in group)
            {
                var actionSize = action.Entity is TableEntity tableEntity ? EntitySplitter.EstimateEntitySize(tableEntity) : 0;

                if (batch.Count > 0 && (batch.Count >= MaxTransactionSize || batchSize + actionSize > EntitySplitter.MaxTransactionPayload))
                {
                    FlushSizedBatch(batch);
                    batch.Clear();
                    batchSize = 0;
                }

                batch.Add(action);
                batchSize += actionSize;
            }

            if (batch.Count > 0)
            {
                FlushSizedBatch(batch);
            }
        }
    }

    /// <summary>
    /// Submit one transaction batch. When the transaction is rejected because of a
    /// single entity, fall back to executing the actions individually so the healthy
    /// entities still land; the first individual failure surfaces to the caller.
    /// </summary>
    private void FlushSizedBatch(List<TableTransactionAction> batch)
    {
        try
        {
            TableClient!.SubmitTransaction(batch, CancellationToken);
        }
        catch (TableTransactionFailedException)
        {
            foreach (var action in batch)
            {
                ExecuteTransactionActionIndividually(action);
            }
        }
    }

    /// <summary>
    /// Execute a single transaction action as its equivalent non-batched operation.
    /// </summary>
    private void ExecuteTransactionActionIndividually(TableTransactionAction action)
    {
        // All actions on this path are created from TableEntity instances; the SDK
        // serializes the concrete dictionary-backed type.
        var entity = (TableEntity)action.Entity;
        var etag = action.ETag == default ? ETag.All : action.ETag;

        switch (action.ActionType)
        {
            case TableTransactionActionType.Add:
                TableClient!.AddEntity(entity, CancellationToken);
                break;
            case TableTransactionActionType.UpsertMerge:
                TableClient!.UpsertEntity(entity, TableUpdateMode.Merge, CancellationToken);
                break;
            case TableTransactionActionType.UpsertReplace:
                TableClient!.UpsertEntity(entity, TableUpdateMode.Replace, CancellationToken);
                break;
            case TableTransactionActionType.UpdateMerge:
                TableClient!.UpdateEntity(entity, etag, TableUpdateMode.Merge, CancellationToken);
                break;
            case TableTransactionActionType.UpdateReplace:
                TableClient!.UpdateEntity(entity, etag, TableUpdateMode.Replace, CancellationToken);
                break;
            case TableTransactionActionType.Delete:
                try
                {
                    TableClient!.DeleteEntity(entity.PartitionKey, entity.RowKey, etag, CancellationToken);
                }
                catch (RequestFailedException ex) when (ex.Status == 404)
                {
                    // The row is already gone, which is the goal of a delete.
                }
                break;
        }
    }

    /// <summary>
    /// Remove part rows of a previously split entity that are no longer used by its
    /// current version, so their stale properties cannot resurface on reassembly.
    /// </summary>
    private void RemoveStalePartRows(string partitionKey, string originalRowKey, HashSet<string> liveRowKeys)
    {
        var filter = $"PartitionKey eq '{EscapeODataValue(partitionKey)}' and {EntitySplitter.OriginalEntityIdKey} eq '{EscapeODataValue(originalRowKey)}'";

        var staleActions = TableClient!.Query<TableEntity>(filter, null, KeysOnlyProperties, CancellationToken)
            .Where(e => !liveRowKeys.Contains(e.RowKey))
            .Select(e => new TableTransactionAction(TableTransactionActionType.Delete, e))
            .ToList();

        if (staleActions.Count > 0)
        {
            SubmitTransactionSized(staleActions);
        }
    }

    /// <summary>
    /// Escape a value for use inside single quotes in an OData filter.
    /// </summary>
    private static string EscapeODataValue(string value) => value.Replace("'", "''");

    #endregion
}
