using System;
using System.Buffers;
using System.Collections.Concurrent;
using System.Collections.Generic;
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

        // ── parsed-byte accounting (for the data-locality scheduler / memory measurement) ──
        // Backing-buffer bytes of each currently-live type document, the running sum, and the peak
        // sum seen. In the default (union) path nothing is released so peak == union total; the
        // scheduler releases a type once its last consumer has run, which keeps the live sum — and
        // thus peak — near the largest co-resident set instead of the whole union.
        private readonly object _acct = new();
        private readonly Dictionary<string, long> _typeBytes = new(StringComparer.OrdinalIgnoreCase);
        private long _liveBytes;
        private long _peakBytes;

        /// <summary>
        /// Opt-in recording sink: when set, every <see cref="Get"/>/<see cref="Has"/> adds the
        /// requested type to it. The engine points this at a per-test set to discover which cached
        /// types each test reads. Null (default) = no recording, zero cost.
        /// </summary>
        public ISet<string>? RecordSink { get; set; }

        /// <summary>Peak sum of live type-document backing bytes over this instance's lifetime.</summary>
        public long PeakBytes { get { lock (_acct) return _peakBytes; } }

        /// <summary>Current sum of live type-document backing bytes.</summary>
        public long LiveBytes { get { lock (_acct) return _liveBytes; } }

        /// <summary>Snapshot of per-type backing bytes seen so far (type → bytes).</summary>
        public Dictionary<string, long> SnapshotTypeSizes()
        {
            lock (_acct) return new Dictionary<string, long>(_typeBytes, StringComparer.OrdinalIgnoreCase);
        }

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

            RecordSink?.Add(type);

            // The default Lazy<T>(factory) mode is ExecutionAndPublication: exactly one thread
            // runs Build, everyone else blocks then sees the same document — the single-flight.
            var lazy = _docs.GetOrAdd(type, t => new Lazy<JsonDocument>(() => Build(t)));
            return lazy.Value.RootElement;
        }

        /// <summary>True when <paramref name="type"/> has at least one record.</summary>
        public bool Has(string type) => Get(type).GetArrayLength() > 0;

        /// <summary>
        /// Release one type's parsed document, freeing its backing bytes immediately instead of at
        /// Dispose. Safe and rebuildable: the entry is removed, so a later <see cref="Get"/> simply
        /// re-reads and re-parses it (results are never affected — only memory). Called by the
        /// data-locality scheduler once a type's last consumer has run.
        /// </summary>
        public long Release(string type)
        {
            if (string.IsNullOrEmpty(type)) return 0;
            if (!_docs.TryRemove(type, out var lazy)) return 0;
            if (lazy.IsValueCreated)
            {
                var doc = lazy.Value;
                if (!ReferenceEquals(doc, EmptyArray)) doc.Dispose();
            }
            lock (_acct)
            {
                if (_typeBytes.TryGetValue(type, out var b))
                {
                    _liveBytes -= b;
                    _typeBytes.Remove(type);
                    return b;
                }
            }
            return 0;
        }

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
            var bytes = buffer.WrittenSpan.ToArray();
            lock (_acct)
            {
                _typeBytes[type] = bytes.LongLength;
                _liveBytes += bytes.LongLength;
                if (_liveBytes > _peakBytes) _peakBytes = _liveBytes;
            }
            return JsonDocument.Parse(bytes);
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
