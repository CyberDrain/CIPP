using System;
using System.Buffers;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Text;
using System.Text.Json;
using Newtonsoft.Json;

namespace CIPP
{
    /// <summary>
    /// Fast JSON -> PowerShell converter for the CippReportingDB read path, replacing
    /// `ConvertFrom-Json` in New-CIPPDbRequest.
    ///
    /// COMPATIBILITY: reproduces ConvertFrom-Json's observable semantics, because every caller
    /// depends on them and any divergence fails *silently*:
    ///   - PSCustomObject records, so `$x[0]`, `$x.Count` and `$x.PSObject.Properties` all keep
    ///     the scalar semantics callers rely on. Hashtable output is cheaper but changes those,
    ///     and only when a pipeline yields exactly one record — do not switch.
    ///   - ISO-8601-looking strings become [DateTime] (tests compare these against [datetime]).
    ///   - Every integer becomes Int64 regardless of magnitude (never Int32).
    /// Matching these costs nothing measurable, so there is no reason to ship divergence.
    ///
    /// PERFORMANCE: without a field list this is modestly faster and allocates less than
    /// ConvertFrom-Json, but retains the SAME live bytes — the parser was never the memory cost.
    /// The memory win comes from <paramref name="fields"/>: not materializing unread fields.
    /// </summary>
    public static class CippJson
    {
        private static readonly JsonDocumentOptions Opts = new JsonDocumentOptions { MaxDepth = 1024 };

        /// <summary>Convert a JSON document, materializing every field.</summary>
        public static object? ConvertFromJson(string json) => ConvertFromJson(json, null);

        /// <summary>
        /// Convert a JSON document, keeping only <paramref name="fields"/> on each RECORD.
        ///
        /// Projection applies at the record level only: for an object root, the root's own fields;
        /// for an array root, each element's own fields. A field that is kept keeps its ENTIRE
        /// subtree — projection never reaches inside a retained value. Null/empty keeps everything.
        ///
        /// The saving therefore scales with how much of the record is dropped: large for
        /// scalar-only field sets, small when a kept subtree is most of the payload.
        /// </summary>
        public static object? ConvertFromJson(string json, string[]? fields)
        {
            if (string.IsNullOrEmpty(json)) return null;

            HashSet<string>? keep = (fields != null && fields.Length > 0)
                ? new HashSet<string>(fields, StringComparer.OrdinalIgnoreCase)
                : null;

            using var doc = JsonDocument.Parse(json, Opts);
            return ReadRoot(doc.RootElement, keep);
        }

        /// <summary>
        /// ConvertFromJson for each text, in one call: a page of rows costs one PowerShell-to-.NET call instead of one per
        /// row, which measured ~2.5x the parse itself. A null, empty or unparseable text gives null at its index.
        /// </summary>
        public static object?[] ConvertFromJsonEach(IList<string?> texts)
        {
            var result = new object?[texts.Count];
            for (int i = 0; i < result.Length; i++)
            {
                try { result[i] = ConvertFromJson(texts[i] ?? ""); }
                catch (Exception) { result[i] = null; }
            }
            return result;
        }

        /// <summary>
        /// A CIPPRestClient response body, parsed straight from its UTF-8 bytes: the same result as
        /// ConvertFromJson(response.Content) without decoding the body into a string first.
        /// </summary>
        public static object? ConvertFromResponse(HttpResult response)
        {
            var json = response.ContentBytes is { } bytes ? HttpBody.Utf8(bytes) : null;
            if (json is null) return ConvertFromJson(response.Content);
            if (json.Value.Length == 0) return null;
            using var doc = JsonDocument.Parse(json.Value, Opts);
            return ReadRoot(doc.RootElement, null);
        }

        /// <summary>
        /// Indexes the records of a JSON array without building them: where each one is, and the values of a few of its
        /// top-level string fields (Values[field][record], null when absent or not a plain string). The caller decides
        /// from those which records it needs and builds only them with <see cref="ConvertFromIndex"/>. Null when the
        /// root is not an array.
        /// </summary>
        public static JsonRecordIndex? IndexRecords(HttpResult response, string[] fields)
        {
            var json = response.ContentBytes is { } bytes ? HttpBody.Utf8(bytes) : null;
            return json is null ? IndexRecords(response.Content, fields) : IndexRecords(json.Value, fields);
        }

        public static JsonRecordIndex? IndexRecords(string json, string[] fields)
            => string.IsNullOrEmpty(json) ? null : IndexRecords(Encoding.UTF8.GetBytes(json), fields);

        private static JsonRecordIndex? IndexRecords(ReadOnlyMemory<byte> json, string[] fields)
        {
            var reader = new Utf8JsonReader(json.Span, new JsonReaderOptions { MaxDepth = 1024 });
            if (!reader.Read() || reader.TokenType != JsonTokenType.StartArray) return null;
            var names = new byte[fields.Length][];
            for (int f = 0; f < fields.Length; f++) names[f] = Encoding.UTF8.GetBytes(fields[f]);
            var starts = new List<int>();
            var lengths = new List<int>();
            var values = new List<string?>[fields.Length];
            for (int f = 0; f < fields.Length; f++) values[f] = new List<string?>();
            while (reader.Read() && reader.TokenType != JsonTokenType.EndArray)
            {
                int start = (int)reader.TokenStartIndex;
                var row = new string?[fields.Length];
                if (reader.TokenType == JsonTokenType.StartObject)
                {
                    while (reader.Read() && reader.TokenType == JsonTokenType.PropertyName)
                    {
                        int match = -1;
                        for (int f = 0; f < names.Length && match < 0; f++)
                            if (NameEquals(ref reader, names[f])) match = f;
                        reader.Read();
                        if (match >= 0 && reader.TokenType == JsonTokenType.String) row[match] = reader.GetString();
                        else reader.Skip();
                    }
                }
                else reader.Skip();
                starts.Add(start);
                lengths.Add((int)reader.BytesConsumed - start);
                for (int f = 0; f < fields.Length; f++) values[f].Add(row[f]);
            }
            var columns = new string?[fields.Length][];
            for (int f = 0; f < fields.Length; f++) columns[f] = values[f].ToArray();
            return new JsonRecordIndex(json, starts.ToArray(), lengths.ToArray(), columns);
        }

        // Property names compared without case, as ConvertFrom-Json's PSObjects resolve them; ASCII names only.
        private static bool NameEquals(ref Utf8JsonReader reader, byte[] name)
        {
            if (reader.ValueIsEscaped || reader.HasValueSequence)
                return string.Equals(reader.GetString(), Encoding.UTF8.GetString(name), StringComparison.OrdinalIgnoreCase);
            var span = reader.ValueSpan;
            if (span.Length != name.Length) return false;
            for (int i = 0; i < span.Length; i++)
            {
                int a = span[i], b = name[i];
                if (a == b) continue;
                int la = a | 0x20;
                if (la != (b | 0x20) || la < 'a' || la > 'z') return false;
            }
            return true;
        }

        /// <summary>The records at <paramref name="indices"/> of an indexed array, built as ConvertFromJson builds them.</summary>
        public static object?[] ConvertFromIndex(JsonRecordIndex index, int[] indices)
        {
            var rows = new object?[indices.Length];
            for (int i = 0; i < indices.Length; i++)
            {
                int r = indices[i];
                using var doc = JsonDocument.Parse(index.Json.Slice(index.Starts[r], index.Lengths[r]), Opts);
                rows[i] = ReadRecord(doc.RootElement, null);
            }
            return rows;
        }

        // Records live at the root, or one level down if the root is an array.
        private static object? ReadRoot(JsonElement root, HashSet<string>? keep)
        {
            if (root.ValueKind == JsonValueKind.Array)
            {
                var rows = new object?[root.GetArrayLength()];
                int r = 0;
                foreach (var item in root.EnumerateArray()) rows[r++] = ReadRecord(item, keep);
                return rows;
            }

            return ReadRecord(root, keep);
        }

        /// <summary>A record: the one level at which projection applies.</summary>
        private static object? ReadRecord(JsonElement el, HashSet<string>? keep)
        {
            if (el.ValueKind != JsonValueKind.Object) return ReadValue(el);

            var pso = new PSObject();
            foreach (var p in el.EnumerateObject())
            {
                // Skipped fields are never materialized — this is the whole point of projection.
                if (keep != null && !keep.Contains(p.Name)) continue;
                PSMembers.AddNoteProperty(pso, p.Name, ReadValue(p.Value));  // kept => whole subtree
            }
            return pso;
        }

        /// <summary>
        /// One string field of each record (array root) or of the record (object root), without building
        /// the records: what `@((ConvertFromJson $json).field)` gives when every value is a plain string.
        /// A missing or null value is null. Returns null when that is not exact (a value that is not a string,
        /// a string ConvertFrom-Json reads as a date, a non-object record or a repeated field), so the caller
        /// can fall back to ConvertFromJson.
        /// </summary>
        public static string?[]? ReadStringField(string json, string field)
        {
            if (string.IsNullOrEmpty(json)) return null;
            using var doc = JsonDocument.Parse(json, Opts);
            var root = doc.RootElement;
            if (root.ValueKind != JsonValueKind.Array)
                return TryReadStringField(root, field, out var one) ? new[] { one } : null;

            var values = new string?[root.GetArrayLength()];
            int i = 0;
            foreach (var item in root.EnumerateArray())
                if (!TryReadStringField(item, field, out values[i++])) return null;
            return values;
        }

        private static bool TryReadStringField(JsonElement record, string field, out string? value)
        {
            value = null;
            if (record.ValueKind != JsonValueKind.Object) return false;
            bool found = false;
            foreach (var p in record.EnumerateObject())
            {
                if (!string.Equals(p.Name, field, StringComparison.OrdinalIgnoreCase)) continue;
                if (found) return false;
                found = true;
                if (p.Value.ValueKind == JsonValueKind.Null) continue;
                if (p.Value.ValueKind != JsonValueKind.String || ReadString(p.Value) is not string s) return false;
                value = s;
            }
            return true;
        }

        /// <summary>
        /// A JSON string as ConvertFrom-Json reads it: ISO-8601 and "/Date(ms)/" values become DateTime. Newtonsoft
        /// only tries strings of 19-40 chars with a 'T' at index 10, so date-only and minute-precision values stay strings.
        /// </summary>
        private static object ReadString(JsonElement el)
        {
            var s = el.GetString()!;
            if (s.Length >= 19 && s.Length <= 40 && char.IsDigit(s[0]) && s[10] == 'T' && el.TryGetDateTime(out var dt)) return dt;
            return TryParseMicrosoftDate(s, out var msDate) ? msDate : s;
        }

        /// <summary>Newtonsoft's "/Date(ms[+-hhmm])/": UTC, or local time when an offset is present.</summary>
        private static bool TryParseMicrosoftDate(string s, out DateTime value)
        {
            value = default;
            if (s.Length < 9 || !s.StartsWith("/Date(", StringComparison.Ordinal) || !s.EndsWith(")/", StringComparison.Ordinal)) return false;
            var inner = s.AsSpan(6, s.Length - 8);
            int sign = inner.Length > 1 ? inner.Slice(1).IndexOfAny('+', '-') : -1;
            var ms = sign >= 0 ? inner.Slice(0, sign + 1) : inner;
            if (!long.TryParse(ms, NumberStyles.AllowLeadingSign, CultureInfo.InvariantCulture, out long millis)) return false;
            if (sign >= 0)
            {
                var offset = inner.Slice(sign + 1);
                if (offset.Length != 5 || !int.TryParse(offset.Slice(1), NumberStyles.None, CultureInfo.InvariantCulture, out _)) return false;
            }
            DateTime utc;
            try { utc = DateTime.UnixEpoch.AddMilliseconds(millis); } catch (ArgumentOutOfRangeException) { return false; }
            value = sign >= 0 ? utc.ToLocalTime() : utc;
            return true;
        }

        /// <summary>Everything below the record level: materialized in full.</summary>
        private static object? ReadValue(JsonElement el)
        {
            switch (el.ValueKind)
            {
                case JsonValueKind.Object:
                    var pso = new PSObject();
                    foreach (var p in el.EnumerateObject())
                        PSMembers.AddNoteProperty(pso, p.Name, ReadValue(p.Value));
                    return pso;

                case JsonValueKind.Array:
                    var list = new object?[el.GetArrayLength()];
                    int i = 0;
                    foreach (var item in el.EnumerateArray()) list[i++] = ReadValue(item);
                    return list;

                case JsonValueKind.String:
                    return ReadString(el);

                case JsonValueKind.True:  return true;
                case JsonValueKind.False: return false;
                case JsonValueKind.Null:  return null;

                case JsonValueKind.Number:
                    // ConvertFrom-Json yields Int64 for all integers — never narrow to Int32.
                    if (el.TryGetInt64(out long l)) return l;
                    return el.GetDouble();

                default: return null;
            }
        }

        /// <summary>
        /// Serializes like `ConvertTo-Json -InputObject $value -Depth $depth -Compress`, for the values
        /// ConvertFrom-Json and PowerShell-built rows hold: PSCustomObject, IDictionary, IList, string,
        /// bool, numbers, DateTime, Guid, enums and null. Returns null for anything else, or anything
        /// nested deeper than depth, so the caller can fall back to ConvertTo-Json.
        /// </summary>
        public static string? ToJson(object? value, int depth = 100)
        {
            // One builder per thread, taken while in use so a re-entrant call (a script property) gets its own
            var sb = t_builder ?? new StringBuilder(1024);
            t_builder = null;
            try
            {
                using (var w = new JsonTextWriter(new StringWriter(sb, CultureInfo.InvariantCulture)) { Formatting = Formatting.None, ArrayPool = CharPool.Instance })
                {
                    if (!TryWrite(w, value, depth)) return null;
                }
                return sb.ToString();
            }
            finally
            {
                sb.Clear();
                if (sb.Capacity <= MaxPooledBuilderChars) t_builder = sb;
            }
        }

        /// <summary>
        /// The JSON object <paramref name="json"/> cut down to the top-level members named in <paramref name="names"/>
        /// (ordinal, document order), in one pass; null when it is not a JSON object. Throws on invalid JSON.
        /// </summary>
        public static string? SelectMembers(string json, ICollection<string> names)
        {
            using var doc = JsonDocument.Parse(json, Opts);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return null;
            var buffer = new ArrayBufferWriter<byte>();
            using (var w = new Utf8JsonWriter(buffer))
            {
                w.WriteStartObject();
                foreach (var member in doc.RootElement.EnumerateObject())
                    if (names.Contains(member.Name)) member.WriteTo(w);
                w.WriteEndObject();
            }
            return Encoding.UTF8.GetString(buffer.WrittenSpan);
        }

        [ThreadStatic] private static StringBuilder? t_builder;
        private const int MaxPooledBuilderChars = 256 * 1024;

        private sealed class CharPool : IArrayPool<char>
        {
            public static readonly CharPool Instance = new();
            public char[] Rent(int minimumLength) => ArrayPool<char>.Shared.Rent(minimumLength);
            public void Return(char[]? array) { if (array != null) ArrayPool<char>.Shared.Return(array); }
        }

        private static bool TryWrite(JsonTextWriter w, object? v, int depth)
        {
            // An empty pipeline assigned to a variable holds AutomationNull, which ConvertTo-Json writes as null
            if (ReferenceEquals(v, System.Management.Automation.Internal.AutomationNull.Value)) { w.WriteNull(); return true; }
            if (v is PSObject pso)
            {
                if (pso.BaseObject is PSCustomObject)
                {
                    if (depth < 0) return false;
                    w.WriteStartObject();
                    foreach (var p in PSMembers.Available ? PSMembers.InstanceProperties(pso) : pso.Properties)
                    {
                        object? pv;
                        try { pv = p.Value; } catch { return false; }
                        w.WritePropertyName(p.Name);
                        if (!TryWrite(w, pv, depth - 1)) return false;
                    }
                    w.WriteEndObject();
                    return true;
                }
                // ConvertTo-Json ignores note properties on strings and dates only; anything else with
                // them is written as {"value":...}.
                var baseObject = pso.BaseObject;
                if (!(baseObject is string || baseObject is DateTime)
                    && (PSMembers.Available ? PSMembers.HasNoteProperty(pso) : pso.Properties.Match("*", PSMemberTypes.NoteProperty).Count > 0)) return false;
                v = baseObject;
            }

            switch (v)
            {
                case null: w.WriteNull(); return true;
                case string s: w.WriteValue(s); return true;
                case bool b: w.WriteValue(b); return true;
                case long l: w.WriteValue(l); return true;
                case int i: w.WriteValue(i); return true;
                case double d: w.WriteValue(d); return true;
                case decimal m: w.WriteValue(m); return true;
                case DateTime dt: w.WriteValue(dt); return true;
                case Guid g: w.WriteValue(g.ToString()); return true;
                case Enum e: w.WriteValue(Convert.ToInt64(e, CultureInfo.InvariantCulture)); return true;
                case IDictionary dict:
                    if (depth < 0) return false;
                    w.WriteStartObject();
                    foreach (DictionaryEntry e in dict)
                    {
                        w.WritePropertyName(e.Key.ToString() ?? string.Empty);
                        if (!TryWrite(w, e.Value, depth - 1)) return false;
                    }
                    w.WriteEndObject();
                    return true;
                case IList list:
                    if (depth < 0) return false;
                    w.WriteStartArray();
                    foreach (var x in list)
                        if (!TryWrite(w, x, depth - 1)) return false;
                    w.WriteEndArray();
                    return true;
                default:
                    return false;
            }
        }
    }

    /// <summary>A JSON array's records located by <see cref="CippJson.IndexRecords(HttpResult, string[])"/>.</summary>
    public sealed class JsonRecordIndex
    {
        internal JsonRecordIndex(ReadOnlyMemory<byte> json, int[] starts, int[] lengths, string?[][] values)
        {
            Json = json; Starts = starts; Lengths = lengths; Values = values;
        }
        internal ReadOnlyMemory<byte> Json { get; }
        internal int[] Starts { get; }
        internal int[] Lengths { get; }
        /// <summary>Values[field][record]: the indexed fields, in the order asked for.</summary>
        public string?[][] Values { get; }
        public int Count => Starts.Length;
    }
}
