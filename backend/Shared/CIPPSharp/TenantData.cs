using System;
using System.Buffers;
using System.Collections.Concurrent;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// Shared, immutable per-tenant data for one engine call. Each reporting <c>type</c>
    /// (Users, Groups, …) is read from <c>CippReportingDB</c> and parsed into a single
    /// <see cref="JsonDocument"/> whose root is a flat array of record elements — parsed
    /// <b>once</b>, <b>single-flight</b> (via <see cref="Lazy{T}"/> in a
    /// <see cref="ConcurrentDictionary{TKey,TValue}"/>), then read concurrently with no
    /// further allocation. No PSObject graphs are ever built — this is the whole point of
    /// the C# engine (the PS path re-materialised the fat Users set dozens of times, OOMing
    /// large instances).
    /// </summary>
    public sealed class TenantData : IDisposable
    {
        private const string ReportingTable = "CippReportingDB";

        // A JsonDocument.Parse over an empty array literal — the shape Get() returns when a
        // type has no rows. Parsed once, shared read-only.
        private static readonly JsonDocument EmptyArray = JsonDocument.Parse("[]");

        private readonly string _tenantFilter;
        private readonly ITableClient _tables;
        private readonly ILogSink _log;

        // type -> Lazy<JsonDocument>. Lazy gives single-flight: the first Get(type) triggers
        // exactly one parse even under concurrent reads; every later read sees the same doc.
        private readonly ConcurrentDictionary<string, Lazy<JsonDocument>> _docs =
            new(StringComparer.OrdinalIgnoreCase);

        private volatile bool _disposed;

        public TenantData(string tenantFilter, ITableClient tables, ILogSink log)
        {
            _tenantFilter = tenantFilter ?? throw new ArgumentNullException(nameof(tenantFilter));
            _tables = tables ?? throw new ArgumentNullException(nameof(tables));
            _log = log ?? throw new ArgumentNullException(nameof(log));
        }

        /// <summary>
        /// The array root (<see cref="JsonValueKind.Array"/>) of records for <paramref name="type"/>.
        /// Returns an empty-array element when the type has no rows. Safe for concurrent reads.
        /// </summary>
        public JsonElement Get(string type)
        {
            if (_disposed) throw new ObjectDisposedException(nameof(TenantData));
            if (string.IsNullOrEmpty(type)) return EmptyArray.RootElement;

            // The default Lazy<T>(factory) mode is ExecutionAndPublication: exactly one thread
            // runs Build, everyone else blocks then sees the same document — the single-flight.
            var lazy = _docs.GetOrAdd(type, t => new Lazy<JsonDocument>(() => Build(t)));
            return lazy.Value.RootElement;
        }

        /// <summary>True when <paramref name="type"/> has at least one record.</summary>
        public bool Has(string type) => Get(type).GetArrayLength() > 0;

        // Reassembled rows come in as raw JSON strings, each a single object OR an array of
        // objects. Flatten them into one array document so Get() always yields a flat record
        // array — matching the old New-CIPPDbRequest shape (an array-typed row unrolled into
        // the output stream).
        private JsonDocument Build(string type)
        {
            System.Collections.Generic.IReadOnlyList<string> rows;
            try
            {
                rows = _tables.ReadRows(ReportingTable, _tenantFilter, type + "-");
            }
            catch (Exception ex)
            {
                _log.Error($"TenantData: failed to read '{type}' rows", _tenantFilter, null, ex);
                return EmptyArray;
            }

            if (rows == null || rows.Count == 0) return EmptyArray;

            var buffer = new ArrayBufferWriter<byte>();
            using (var writer = new Utf8JsonWriter(buffer))
            {
                writer.WriteStartArray();
                foreach (var row in rows)
                {
                    if (string.IsNullOrWhiteSpace(row)) continue;
                    try
                    {
                        using var doc = JsonDocument.Parse(row);
                        var root = doc.RootElement;
                        if (root.ValueKind == JsonValueKind.Array)
                        {
                            foreach (var el in root.EnumerateArray()) el.WriteTo(writer);
                        }
                        else if (root.ValueKind != JsonValueKind.Null &&
                                 root.ValueKind != JsonValueKind.Undefined)
                        {
                            root.WriteTo(writer);
                        }
                    }
                    catch (JsonException ex)
                    {
                        // Match the old path's -ErrorAction SilentlyContinue: skip bad rows.
                        _log.Warn($"TenantData: skipping unparseable '{type}' row: {ex.Message}",
                            _tenantFilter, null);
                    }
                }
                writer.WriteEndArray();
            }

            // ToArray gives a stable byte[] that the returned JsonDocument keeps rooted for its
            // lifetime (Parse over ReadOnlyMemory does not copy), so the array is not collected
            // out from under it.
            return JsonDocument.Parse(buffer.WrittenSpan.ToArray());
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;
            foreach (var lazy in _docs.Values)
            {
                if (!lazy.IsValueCreated) continue;
                var doc = lazy.Value;
                if (!ReferenceEquals(doc, EmptyArray)) doc.Dispose();
            }
            _docs.Clear();
        }
    }
}
