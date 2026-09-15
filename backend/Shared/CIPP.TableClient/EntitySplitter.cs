using Azure.Data.Tables;
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CIPP.TableClient;

/// <summary>
/// Splits entities that exceed the Azure Table Storage size limits (64 KiB per string
/// property, 1 MiB per entity) into multiple properties and rows, and reassembles
/// them on read.
///
/// Cross-column splitting: an oversized string property "Data" is cut into chunks of
/// at most <see cref="MaxPropertyChars"/> characters, stored as "Data_Part0",
/// "Data_Part1", ... A JSON manifest in the <see cref="SplitOverPropsKey"/> property
/// records which chunk properties belong to which original property, in order:
/// [{"OriginalHeader":"Data","SplitHeaders":["Data_Part0","Data_Part1"]}]. The
/// manifest is read as either an array or a single object.
///
/// Cross-row splitting: when the entity is still over <see cref="MaxRowSize"/> after
/// column splitting, its properties are distributed over multiple rows. The first row
/// keeps the original RowKey, subsequent rows use "{RowKey}-part{i}". Every row
/// carries <see cref="OriginalEntityIdKey"/> (the original RowKey) and
/// <see cref="PartIndexKey"/> (the zero-based row index). Chunks of one property may
/// land on different rows; reassembly merges rows before joining chunks, so the
/// combination is well-defined.
///
/// Reassembly groups rows by (PartitionKey, OriginalEntityId), merges each group in
/// PartIndex order, then rejoins chunked properties per the manifest. A plain row
/// whose RowKey equals the OriginalEntityId of leftover part rows takes precedence,
/// so an entity rewritten small after having been split still reads correctly.
/// </summary>
public static class EntitySplitter
{
    /// <summary>Property holding the JSON manifest describing column-split properties.</summary>
    public const string SplitOverPropsKey = "SplitOverProps";

    /// <summary>Property on part rows holding the RowKey of the original entity.</summary>
    public const string OriginalEntityIdKey = "OriginalEntityId";

    /// <summary>Property on part rows holding the zero-based row index.</summary>
    public const string PartIndexKey = "PartIndex";

    /// <summary>
    /// Property on part rows holding how many rows the entity was split into, so a
    /// reader can tell a complete group from a truncated one.
    /// </summary>
    public const string PartCountKey = "PartCount";

    /// <summary>Default for <see cref="MaxPropertyChars"/>.</summary>
    public const int DefaultMaxPropertyChars = 32_256;

    /// <summary>Default for <see cref="MaxRowSize"/>.</summary>
    public const int DefaultMaxRowSize = 900_000;

    /// <summary>Default for <see cref="MaxTransactionPayload"/>.</summary>
    public const int DefaultMaxTransactionPayload = 2_500_000;

    /// <summary>
    /// Maximum number of characters per chunk when splitting an oversized string
    /// property. The service limit is 64 KiB per string property, i.e. 32768 UTF-16
    /// units regardless of encoding; the default keeps a 512-unit margin below it.
    /// Settable for tuning and testing; the reader accepts any chunk size.
    /// </summary>
    public static int MaxPropertyChars { get; set; } = DefaultMaxPropertyChars;

    /// <summary>
    /// Estimated entity size in bytes at which an entity is distributed over multiple
    /// rows. The service allows 1 MiB per entity, but measures it differently per
    /// implementation: the real service uses the documented UTF-16 size formula while
    /// the storage emulator measures the escaped JSON payload. The estimator counts
    /// the worst case of both, so the default of 900k keeps ~15% headroom against
    /// either. Settable for tuning and testing.
    /// </summary>
    public static int MaxRowSize { get; set; } = DefaultMaxRowSize;

    /// <summary>
    /// Estimated payload budget in bytes for a single transaction. Batch requests cap
    /// at 4 MiB (rejected at ~3.8 MiB empirically); split rows approach
    /// <see cref="MaxRowSize"/> each, so batches must be packed by size as well as
    /// count. The default keeps a comfortable margin for the worst-case encoding.
    /// Settable for tuning and testing.
    /// </summary>
    public static int MaxTransactionPayload { get; set; } = DefaultMaxTransactionPayload;

    /// <summary>
    /// Properties that describe a row rather than the logical entity, excluded when
    /// merging part rows back together.
    /// </summary>
    private static readonly HashSet<string> MergeExcludedProperties = new(StringComparer.Ordinal)
    {
        OriginalEntityIdKey,
        PartIndexKey,
        PartCountKey,
        "PartitionKey",
        "RowKey",
        "Timestamp",
        "odata.etag",
        "ETag",
    };

    /// <summary>
    /// The result of splitting one logical entity into the rows to write.
    /// </summary>
    public sealed class SplitResult
    {
        /// <summary>The physical rows to write. A single row when no splitting was needed.</summary>
        public List<TableEntity> Rows { get; }

        /// <summary>
        /// Whether the splitter rewrote the entity (column chunks and/or multiple rows).
        /// When false, <see cref="Rows"/> contains the original entity untouched.
        /// </summary>
        public bool Engaged { get; }

        public SplitResult(List<TableEntity> rows, bool engaged)
        {
            Rows = rows;
            Engaged = engaged;
        }
    }

    /// <summary>
    /// Split an entity into one or more rows that each fit within the storage limits.
    /// Entities within the limits are passed through untouched.
    /// </summary>
    public static SplitResult Split(TableEntity entity)
    {
        var hasOversizedProperty = entity.Any(p => p.Value is string s && s.Length > MaxPropertyChars);

        if (!hasOversizedProperty && EstimateEntitySize(entity) <= MaxRowSize)
        {
            return new SplitResult(new List<TableEntity> { entity }, false);
        }

        // Rebuild the entity without row-scoped metadata. Split rows are new rows,
        // the source row's Timestamp and ETag do not apply to them
        var working = new TableEntity(entity.PartitionKey, entity.RowKey);
        foreach (var property in entity)
        {
            if (property.Key is "PartitionKey" or "RowKey" or "Timestamp" or "odata.etag" or "ETag")
            {
                continue;
            }
            working[property.Key] = property.Value;
        }

        SplitOversizedProperties(working);

        if (EstimateEntitySize(working) <= MaxRowSize)
        {
            return new SplitResult(new List<TableEntity> { working }, true);
        }

        return new SplitResult(SplitAcrossRows(working), true);
    }

    /// <summary>
    /// Cross-column splitting: replace every oversized string property with chunk
    /// properties and record the manifest in <see cref="SplitOverPropsKey"/>.
    /// </summary>
    private static void SplitOversizedProperties(TableEntity working)
    {
        var manifest = new List<(string OriginalHeader, List<string> SplitHeaders)>();

        foreach (var propertyName in working.Keys.ToList())
        {
            if (working[propertyName] is not string value || value.Length <= MaxPropertyChars)
            {
                continue;
            }

            var chunks = ChunkString(value);
            var chunkNames = new List<string>(chunks.Count);

            working.Remove(propertyName);
            for (var i = 0; i < chunks.Count; i++)
            {
                var chunkName = $"{propertyName}_Part{i}";
                chunkNames.Add(chunkName);
                working[chunkName] = chunks[i];
            }

            manifest.Add((propertyName, chunkNames));
        }

        if (manifest.Count > 0)
        {
            working[SplitOverPropsKey] = SerializeManifest(manifest);
        }
    }

    /// <summary>
    /// Cross-row splitting: distribute the properties of an oversized entity over
    /// multiple rows, filling each row up to <see cref="MaxRowSize"/>.
    /// </summary>
    private static List<TableEntity> SplitAcrossRows(TableEntity working)
    {
        var originalRowKey = working.RowKey;
        var rows = new List<TableEntity>();

        TableEntity CreateRow(int index)
        {
            var rowKey = index == 0 ? originalRowKey : $"{originalRowKey}-part{index}";
            var row = new TableEntity(working.PartitionKey, rowKey)
            {
                [OriginalEntityIdKey] = originalRowKey,
                [PartIndexKey] = index,
            };
            return row;
        }

        var rowIndex = 0;
        var currentRow = CreateRow(rowIndex);
        var currentSize = EstimateEntitySize(currentRow);

        // The manifest goes on the root row after the loop; charge it here so it cannot
        // push that row over the limit.
        if (working.TryGetValue(SplitOverPropsKey, out var manifestForBudget))
        {
            currentSize += EstimatePropertySize(SplitOverPropsKey, manifestForBudget);
        }

        foreach (var property in working)
        {
            if (property.Key is "PartitionKey" or "RowKey")
            {
                continue;
            }

            // Placed on the root row below instead. Left to the loop it lands on the
            // last row, and a reader holding only the first row would then have every
            // chunk and nothing describing them.
            if (property.Key == SplitOverPropsKey)
            {
                continue;
            }

            var propertySize = EstimatePropertySize(property.Key, property.Value);

            // Start a new row when this property would push the current one over the
            // budget. A row always accepts at least one property so a single property
            // larger than the budget cannot loop forever.
            if (currentSize + propertySize > MaxRowSize && HasPayload(currentRow))
            {
                rows.Add(currentRow);
                rowIndex++;
                currentRow = CreateRow(rowIndex);
                currentSize = EstimateEntitySize(currentRow);
            }

            currentRow[property.Key] = property.Value;
            currentSize += propertySize;
        }

        rows.Add(currentRow);

        if (working.TryGetValue(SplitOverPropsKey, out var manifest))
        {
            rows[0][SplitOverPropsKey] = manifest;
        }

        // On every row, so any subset of them knows how many there should be.
        foreach (var row in rows)
        {
            row[PartCountKey] = rows.Count;
        }

        return rows;
    }

    /// <summary>
    /// Whether a row under construction holds any property beyond keys and part markers.
    /// </summary>
    private static bool HasPayload(TableEntity row) =>
        row.Keys.Any(k => k is not ("PartitionKey" or "RowKey" or OriginalEntityIdKey or PartIndexKey));

    /// <summary>
    /// Split a string into chunks of at most <see cref="MaxPropertyChars"/> characters,
    /// never cutting between the halves of a surrogate pair.
    /// </summary>
    private static List<string> ChunkString(string value)
    {
        var chunks = new List<string>((value.Length + MaxPropertyChars - 1) / MaxPropertyChars);
        var position = 0;

        while (position < value.Length)
        {
            var length = Math.Min(MaxPropertyChars, value.Length - position);

            // Move the boundary back one character rather than splitting a surrogate pair.
            if (position + length < value.Length && char.IsHighSurrogate(value[position + length - 1]) && length > 1)
            {
                length--;
            }

            chunks.Add(value.Substring(position, length));
            position += length;
        }

        return chunks;
    }

    /// <summary>
    /// Serialize the manifest of column-split properties as a JSON array.
    /// </summary>
    private static string SerializeManifest(List<(string OriginalHeader, List<string> SplitHeaders)> manifest)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartArray();
            foreach (var (originalHeader, splitHeaders) in manifest)
            {
                writer.WriteStartObject();
                writer.WriteString("OriginalHeader", originalHeader);
                writer.WritePropertyName("SplitHeaders");
                writer.WriteStartArray();
                foreach (var header in splitHeaders)
                {
                    writer.WriteStringValue(header);
                }
                writer.WriteEndArray();
                writer.WriteEndObject();
            }
            writer.WriteEndArray();
        }

        return Encoding.UTF8.GetString(stream.ToArray());
    }

    /// <summary>
    /// Reassemble physical rows into logical entities: merge part rows in PartIndex
    /// order, prefer plain rows over leftover part rows with the same identity, and
    /// rejoin column-split properties according to their manifest.
    /// </summary>
    /// <param name="entities">The physical rows, e.g. the result of a table query.</param>
    /// <param name="onWarning">Called with a message when a malformed manifest is skipped.</param>
    /// <param name="onIncomplete">
    /// Called for each entity whose rows or split-property chunks are missing. That entity
    /// is left out of the results and the rest are still returned, so one entity with rows
    /// missing does not hide the entities returned alongside it.
    /// </param>
    public static IEnumerable<TableEntity> Reassemble(IEnumerable<TableEntity> entities, Action<string>? onWarning = null, Action<IncompleteEntityException>? onIncomplete = null)
    {
        var (order, groups) = GroupRows(entities);

        foreach (var key in order)
        {
            var group = groups[key];

            TableEntity? result;
            if (group.Root is not null)
            {
                result = group.Root;
            }
            else if (group.Parts.Count > 0)
            {
                if (DescribeIncompleteness(group) is { } reason)
                {
                    onIncomplete?.Invoke(new IncompleteEntityException(
                        key.PartitionKey,
                        key.EntityId,
                        $"Skipped entity with PartitionKey='{key.PartitionKey}' and RowKey='{key.EntityId}': {reason}"));
                    continue;
                }

                result = MergeParts(group.Parts, key.PartitionKey, key.EntityId);
            }
            else
            {
                continue;
            }

            try
            {
                JoinSplitProperties(result, onWarning);
            }
            catch (IncompleteEntityException ex)
            {
                onIncomplete?.Invoke(ex);
                continue;
            }

            yield return result;
        }
    }

    /// <summary>
    /// Group physical rows by the logical entity they belong to, preserving first-seen
    /// order.
    /// </summary>
    private static (List<(string PartitionKey, string EntityId)> Order, Dictionary<(string PartitionKey, string EntityId), EntityGroup> Groups) GroupRows(IEnumerable<TableEntity> entities)
    {
        var order = new List<(string PartitionKey, string EntityId)>();
        var groups = new Dictionary<(string PartitionKey, string EntityId), EntityGroup>();

        foreach (var entity in entities)
        {
            var isPart = TryGetOriginalEntityId(entity, out var originalEntityId);
            var key = (entity.PartitionKey, isPart ? originalEntityId : entity.RowKey);

            if (!groups.TryGetValue(key, out var group))
            {
                group = new EntityGroup();
                groups[key] = group;
                order.Add(key);
            }

            if (!isPart)
            {
                // A plain row is the authoritative version of this identity: any part
                // rows with the same identity are stale leftovers from an earlier,
                // larger version of the entity and are dropped.
                group.Root = entity;
                group.Parts.Clear();
            }
            else if (group.Root is null)
            {
                group.Parts.Add(entity);
            }
        }

        return (order, groups);
    }

    /// <summary>
    /// The identities of entities that are present only in part, i.e. rows were split
    /// over more rows than the given set contains.
    /// </summary>
    /// <remarks>
    /// Lets a reader fetch the rows it is missing before reassembling, instead of
    /// producing a truncated entity from what it has.
    /// </remarks>
    /// <param name="entities">The physical rows, e.g. the result of a table query.</param>
    public static IReadOnlyList<(string PartitionKey, string EntityId)> FindIncompleteGroups(IEnumerable<TableEntity> entities)
    {
        var (order, groups) = GroupRows(entities);
        var incomplete = new List<(string PartitionKey, string EntityId)>();

        foreach (var key in order)
        {
            var group = groups[key];
            if (group.Root is null && group.Parts.Count > 0 && DescribeIncompleteness(group) is not null)
            {
                incomplete.Add(key);
            }
        }

        return incomplete;
    }

    /// <summary>
    /// Why a group of part rows is not the whole entity, or null when it is.
    /// </summary>
    /// <remarks>
    /// <see cref="PartCountKey"/> answers this outright. Rows written before it existed
    /// fall back to two weaker signals: indexes must run from zero without gaps, and a
    /// group holding chunk properties must also hold the manifest describing them,
    /// which older writers put on the last row.
    /// </remarks>
    private static string? DescribeIncompleteness(EntityGroup group)
    {
        var indexes = group.Parts.Select(GetPartIndex).OrderBy(i => i).ToList();

        var declaredCount = group.Parts
            .Select(GetPartCount)
            .Where(c => c > 0)
            .DefaultIfEmpty(0)
            .Max();

        if (declaredCount > 0 && group.Parts.Count != declaredCount)
        {
            return $"the entity was split over {declaredCount} rows but only {group.Parts.Count} were returned.";
        }

        if (indexes[0] != 0)
        {
            return $"the first row of the entity (PartIndex 0) was not returned.";
        }

        for (var i = 1; i < indexes.Count; i++)
        {
            if (indexes[i] != indexes[i - 1] + 1)
            {
                return $"the rows returned skip from PartIndex {indexes[i - 1]} to {indexes[i]}.";
            }
        }

        if (declaredCount == 0 &&
            !group.Parts.Any(p => p.ContainsKey(SplitOverPropsKey)) &&
            group.Parts.Any(p => p.Keys.Any(IsChunkPropertyName)))
        {
            return "the entity holds split property chunks but no manifest describing them, so the row carrying the manifest was not returned.";
        }

        return null;
    }

    /// <summary>
    /// Whether a property name looks like one of the chunks a column-split property was
    /// broken into, i.e. ends in <c>_Part</c> followed by digits.
    /// </summary>
    private static bool IsChunkPropertyName(string name)
    {
        var separator = name.LastIndexOf("_Part", StringComparison.Ordinal);
        if (separator < 1 || separator + 5 >= name.Length)
        {
            return false;
        }

        for (var i = separator + 5; i < name.Length; i++)
        {
            if (name[i] < '0' || name[i] > '9')
            {
                return false;
            }
        }

        return true;
    }

    /// <summary>
    /// The PartCount of a part row, tolerating the integer widening that occurs when
    /// rows round-trip through JSON. Rows written before the property existed report 0.
    /// </summary>
    private static long GetPartCount(TableEntity entity)
    {
        if (!entity.TryGetValue(PartCountKey, out var value))
        {
            return 0;
        }

        return value switch
        {
            int i => i,
            long l => l,
            string s when long.TryParse(s, out var parsed) => parsed,
            _ => 0,
        };
    }

    private sealed class EntityGroup
    {
        public TableEntity? Root { get; set; }
        public List<TableEntity> Parts { get; } = new();
    }

    /// <summary>
    /// Whether the row is a part of a split entity, i.e. carries a non-empty
    /// <see cref="OriginalEntityIdKey"/> property.
    /// </summary>
    private static bool TryGetOriginalEntityId(TableEntity entity, out string originalEntityId)
    {
        if (entity.TryGetValue(OriginalEntityIdKey, out var value) && value?.ToString() is { Length: > 0 } id)
        {
            originalEntityId = id;
            return true;
        }

        originalEntityId = string.Empty;
        return false;
    }

    /// <summary>
    /// The PartIndex of a part row, tolerating the integer widening that occurs when
    /// rows round-trip through JSON. Rows without a usable index sort first.
    /// </summary>
    private static long GetPartIndex(TableEntity entity)
    {
        if (!entity.TryGetValue(PartIndexKey, out var value))
        {
            return long.MinValue;
        }

        return value switch
        {
            int i => i,
            long l => l,
            string s when long.TryParse(s, out var parsed) => parsed,
            _ => long.MinValue,
        };
    }

    /// <summary>
    /// Merge part rows into one logical entity in PartIndex order. Row-scoped metadata
    /// is dropped; the merged entity takes its RowKey from the original entity id and
    /// its Timestamp and ETag from the first part row.
    /// </summary>
    private static TableEntity MergeParts(List<TableEntity> parts, string partitionKey, string originalEntityId)
    {
        var ordered = parts.OrderBy(GetPartIndex).ToList();
        var merged = new TableEntity(partitionKey, originalEntityId);

        foreach (var part in ordered)
        {
            foreach (var property in part)
            {
                if (MergeExcludedProperties.Contains(property.Key))
                {
                    continue;
                }

                // The writer places each property on exactly one row; string values
                // colliding across rows are treated as fragments and concatenated.
                if (merged.TryGetValue(property.Key, out var existing) && existing is string left && property.Value is string right)
                {
                    merged[property.Key] = left + right;
                }
                else
                {
                    merged[property.Key] = property.Value;
                }
            }
        }

        var first = ordered[0];
        merged.Timestamp = first.Timestamp;
        if (first.TryGetValue("odata.etag", out var etag))
        {
            merged["odata.etag"] = etag;
        }

        return merged;
    }

    /// <summary>
    /// Rejoin column-split properties according to the <see cref="SplitOverPropsKey"/>
    /// manifest, removing the chunk properties and the manifest itself. Malformed
    /// manifests are reported through <paramref name="onWarning"/> and skipped; the
    /// manifest property is removed either way.
    /// </summary>
    private static void JoinSplitProperties(TableEntity entity, Action<string>? onWarning)
    {
        if (!entity.TryGetValue(SplitOverPropsKey, out var manifestValue) || manifestValue is not string manifestJson || manifestJson.Length == 0)
        {
            return;
        }

        try
        {
            using var document = JsonDocument.Parse(manifestJson);

            // The manifest may be a bare object instead of a single-element array.
            var entries = document.RootElement.ValueKind switch
            {
                JsonValueKind.Array => document.RootElement.EnumerateArray().ToList(),
                JsonValueKind.Object => new List<JsonElement> { document.RootElement },
                _ => throw new JsonException($"Unexpected manifest root of kind {document.RootElement.ValueKind}."),
            };

            foreach (var entry in entries)
            {
                if (!entry.TryGetProperty("OriginalHeader", out var originalHeaderElement) ||
                    originalHeaderElement.GetString() is not { Length: > 0 } originalHeader ||
                    !entry.TryGetProperty("SplitHeaders", out var splitHeadersElement))
                {
                    throw new JsonException("Manifest entry is missing OriginalHeader or SplitHeaders.");
                }

                var splitHeaders = splitHeadersElement.ValueKind switch
                {
                    JsonValueKind.Array => splitHeadersElement.EnumerateArray()
                        .Select(h => h.GetString())
                        .Where(h => h is { Length: > 0 })
                        .Select(h => h!)
                        .ToList(),
                    // Single-element unwrapping tolerance, should not occur in practice.
                    JsonValueKind.String when splitHeadersElement.GetString() is { Length: > 0 } single => new List<string> { single },
                    _ => throw new JsonException("Manifest SplitHeaders is neither an array nor a string."),
                };

                var joined = new StringBuilder();
                foreach (var header in splitHeaders)
                {
                    // Skipping a missing chunk would store the rest as though it were the
                    // whole value - a truncation nothing downstream can detect.
                    if (!entity.TryGetValue(header, out var chunk) || chunk is null)
                    {
                        throw new IncompleteEntityException(
                            entity.PartitionKey,
                            entity.RowKey,
                            $"Cannot reassemble property '{originalHeader}' of entity with PartitionKey='{entity.PartitionKey}' and RowKey='{entity.RowKey}': chunk property '{header}' is missing. The query did not return every row the entity was split over.");
                    }

                    joined.Append(chunk);
                }

                entity[originalHeader] = joined.ToString();
                foreach (var header in splitHeaders)
                {
                    entity.Remove(header);
                }
            }
        }
        catch (Exception ex) when (ex is JsonException or InvalidOperationException)
        {
            onWarning?.Invoke($"Failed to process {SplitOverPropsKey} for entity with PartitionKey='{entity.PartitionKey}' and RowKey='{entity.RowKey}': {ex.Message}");
        }
        finally
        {
            entity.Remove(SplitOverPropsKey);
        }
    }

    /// <summary>
    /// Estimate the stored size of an entity in bytes, based on the documented Azure
    /// Table Storage entity size formula (property names and string values count as
    /// UTF-16, i.e. two bytes per character).
    /// </summary>
    public static int EstimateEntitySize(TableEntity entity)
    {
        var size = 4;
        size += (entity.PartitionKey?.Length ?? 0) * 2;
        size += (entity.RowKey?.Length ?? 0) * 2;

        foreach (var property in entity)
        {
            if (property.Key is "PartitionKey" or "RowKey" or "Timestamp" or "odata.etag")
            {
                continue;
            }
            size += EstimatePropertySize(property.Key, property.Value);
        }

        return size;
    }

    /// <summary>
    /// Estimate the stored size of a single property in bytes: fixed per-property
    /// overhead, the name, and the value by type. Sizes are the maximum of the
    /// documented storage size formula and the JSON wire representation, since the
    /// service enforces the entity limit against whichever is relevant to it (the
    /// emulator measures the request payload, where non-ASCII characters are escaped
    /// as \uXXXX sequences). Non-string types include headroom for the OData type
    /// annotation property that accompanies them on the wire.
    /// </summary>
    private static int EstimatePropertySize(string name, object? value)
    {
        var valueSize = value switch
        {
            null => 0,
            string s => EstimateStringSize(s),
            byte[] b => EstimateBinarySize(b.Length),
            BinaryData b => EstimateBinarySize((int)Math.Min(b.ToMemory().Length, int.MaxValue)),
            bool => 8,
            int => 16,
            long => 48,
            double => 48,
            Guid => 64,
            DateTime => 72,
            DateTimeOffset => 72,
            _ => EstimateStringSize(value.ToString() ?? string.Empty),
        };

        return 8 + name.Length * 2 + valueSize;
    }

    /// <summary>
    /// Estimate the stored size of a string value in bytes. Per UTF-16 unit, the cost
    /// is the maximum of the storage formula (2 bytes per unit) and the escaped JSON
    /// wire form (6 bytes for control and non-ASCII units).
    /// </summary>
    private static int EstimateStringSize(string value)
    {
        var size = 4;
        foreach (var c in value)
        {
            size += c < 0x20 || c >= 0x80 ? 6 : 2;
        }
        return size;
    }

    /// <summary>
    /// Estimate the stored size of a binary value in bytes: the maximum of the storage
    /// formula (raw bytes + 4 overhead) and the base64 JSON wire form. Base64 encodes
    /// every 3 bytes as 4 characters; ceiling division ((length + 2) / 3 * 4)
    /// is used so a length not divisible by 3 is not underestimated. The +44 covers
    /// the OData type annotation property that accompanies binary values on the wire.
    /// </summary>
    private static int EstimateBinarySize(int length) =>
        Math.Max(length + 4, (length + 2) / 3 * 4 + 44);
}
