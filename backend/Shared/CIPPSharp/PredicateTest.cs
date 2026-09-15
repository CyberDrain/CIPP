using System;
using System.Collections.Generic;
using System.Globalization;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace CIPP.Tests
{
    /// <summary>
    /// A generic, config-driven test: the <see cref="ConfigRule"/> <i>is</i> the test. Reads one
    /// reporting type, AND-filters rows with <c>where</c>, grades them with <c>expect</c>
    /// (all/none/count/percent), and renders pass/fail markdown — evaluated purely over
    /// <see cref="JsonElement"/>, never building object graphs. Anything a rule can't express is a
    /// hand-written class test instead.
    /// </summary>
    public sealed class PredicateTest : ICippTest
    {
        /// <summary>Max failing rows rendered in the fail table before truncation.</summary>
        public const int FailTableLimit = 100;

        private readonly ConfigRule _rule;

        public PredicateTest(string id, ConfigRule rule)
        {
            Id = id ?? throw new ArgumentNullException(nameof(id));
            _rule = rule ?? throw new ArgumentNullException(nameof(rule));
        }

        public string Id { get; }

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var rows = data.Get(_rule.Type);
            if (rows.ValueKind != JsonValueKind.Array || rows.GetArrayLength() == 0)
            {
                return new CippTestResult(
                    TestStatus.Skipped,
                    $"No {_rule.Type} data found in database. Data collection may not yet have run for this tenant.");
            }

            var expect = _rule.Expect ?? new ConfigExpect();

            // Population: rows matching every `where` clause (empty where = all rows).
            var matched = new List<JsonElement>();
            foreach (var row in rows.EnumerateArray())
            {
                if (MatchesAll(row, _rule.Where)) matched.Add(row);
            }

            // Grade each matched row against the AND of `of`. "failing" is the offending set the
            // fail table renders — the meaning of "offending" depends on the mode.
            var satisfyingRows = new List<JsonElement>();
            var notSatisfying = new List<JsonElement>();
            foreach (var row in matched)
            {
                if (MatchesAll(row, expect.Of)) satisfyingRows.Add(row);
                else notSatisfying.Add(row);
            }
            int satisfying = satisfyingRows.Count;

            bool passed;
            List<JsonElement> failing;
            double threshold = expect.Threshold ?? 0d;
            double pct = Markdown.Percent(satisfying, matched.Count);

            switch ((expect.Mode ?? "all").ToLowerInvariant())
            {
                case "none":
                    // No matched row may satisfy `of` (the "bad" condition). Offenders satisfy it.
                    passed = satisfyingRows.Count == 0;
                    failing = satisfyingRows;
                    break;

                case "count":
                    // At least `threshold` matched rows must satisfy `of`.
                    passed = satisfying >= threshold;
                    failing = notSatisfying;
                    break;

                case "percent":
                    // At least `threshold`% of matched rows must satisfy `of`.
                    passed = pct >= threshold;
                    failing = notSatisfying;
                    break;

                case "all":
                default:
                    // Every matched row must satisfy `of`. Offenders are the ones that don't.
                    passed = notSatisfying.Count == 0;
                    failing = notSatisfying;
                    break;
            }

            var tokens = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                ["matched"] = matched.Count.ToString(CultureInfo.InvariantCulture),
                ["satisfying"] = satisfying.ToString(CultureInfo.InvariantCulture),
                ["failing"] = failing.Count.ToString(CultureInfo.InvariantCulture),
                ["total"] = matched.Count.ToString(CultureInfo.InvariantCulture),
                ["pct"] = pct.ToString(CultureInfo.InvariantCulture),
                ["threshold"] = threshold.ToString(CultureInfo.InvariantCulture),
            };

            string dataJson = BuildResultDataJson(matched.Count, satisfying, failing.Count, expect.Mode ?? "all", threshold, pct);

            if (passed)
            {
                var text = Substitute(_rule.Pass ?? $"All {matched.Count} {_rule.Type} records met the expectation.", tokens);
                return new CippTestResult(TestStatus.Passed, text, dataJson);
            }
            else
            {
                var sb = new StringBuilder();
                sb.Append(Substitute(_rule.Fail ?? $"{failing.Count} {_rule.Type} records did not meet the expectation.", tokens));
                if (_rule.FailTable.Count > 0 && failing.Count > 0)
                {
                    sb.Append("\n\n");
                    sb.Append(BuildFailTable(failing));
                }
                return new CippTestResult(TestStatus.Failed, sb.ToString(), dataJson);
            }
        }

        // ── clause evaluation ─────────────────────────────────────────────────────
        private static bool MatchesAll(JsonElement row, List<ConfigClause>? clauses)
        {
            if (clauses == null || clauses.Count == 0) return true;
            foreach (var clause in clauses)
                if (!Matches(row, clause)) return false;
            return true;
        }

        private static bool Matches(JsonElement row, ConfigClause clause)
        {
            var found = TryGetField(row, clause.Field, out var field);
            var op = (clause.Op ?? "").ToLowerInvariant();

            switch (op)
            {
                case "exists":
                    return found && field.ValueKind != JsonValueKind.Null;
                case "notexists":
                    return !found || field.ValueKind == JsonValueKind.Null;
            }

            // For every value-comparing op, a missing/null field cannot match (except notContains,
            // handled below where "not present" reads as "does not contain").
            switch (op)
            {
                case "eq":
                    return found && ValueEquals(field, clause.Value);
                case "ne":
                    return !(found && ValueEquals(field, clause.Value));
                case "gt":
                    return found && Compare(field, clause.Value) is int g && g > 0;
                case "ge":
                    return found && Compare(field, clause.Value) is int ge && ge >= 0;
                case "lt":
                    return found && Compare(field, clause.Value) is int l && l < 0;
                case "le":
                    return found && Compare(field, clause.Value) is int le && le <= 0;
                case "contains":
                    return found && Contains(field, clause.Value);
                case "notcontains":
                    return !(found && Contains(field, clause.Value));
                case "like":
                    return found && Like(field, clause.Value);
                default:
                    return false;
            }
        }

        // Case-insensitive, dot-path field lookup. Walks nested objects; stops at non-objects.
        private static bool TryGetField(JsonElement row, string path, out JsonElement value)
        {
            value = default;
            if (row.ValueKind != JsonValueKind.Object || string.IsNullOrEmpty(path)) return false;

            var current = row;
            foreach (var segment in path.Split('.'))
            {
                if (current.ValueKind != JsonValueKind.Object) return false;
                if (current.TryGetProperty(segment, out var next))
                {
                    current = next;
                    continue;
                }
                // Case-insensitive fallback.
                bool hit = false;
                foreach (var prop in current.EnumerateObject())
                {
                    if (string.Equals(prop.Name, segment, StringComparison.OrdinalIgnoreCase))
                    {
                        current = prop.Value;
                        hit = true;
                        break;
                    }
                }
                if (!hit) return false;
            }
            value = current;
            return true;
        }

        private static bool ValueEquals(JsonElement field, JsonElement val)
        {
            switch (val.ValueKind)
            {
                case JsonValueKind.True:
                case JsonValueKind.False:
                    var vb = val.ValueKind == JsonValueKind.True;
                    if (field.ValueKind == JsonValueKind.True) return vb;
                    if (field.ValueKind == JsonValueKind.False) return !vb;
                    if (field.ValueKind == JsonValueKind.String &&
                        bool.TryParse(field.GetString(), out var fb)) return fb == vb;
                    return false;

                case JsonValueKind.Number:
                    return TryAsDouble(field, out var fd) && TryAsDouble(val, out var nd) && fd == nd;

                case JsonValueKind.String:
                    return string.Equals(AsString(field), val.GetString(), StringComparison.OrdinalIgnoreCase);

                case JsonValueKind.Null:
                    return field.ValueKind == JsonValueKind.Null;

                default:
                    return false;
            }
        }

        // Numeric compare when both coerce to numbers, else ordinal-ignore-case string compare.
        private static int? Compare(JsonElement field, JsonElement val)
        {
            if (TryAsDouble(field, out var fd) && TryAsDouble(val, out var vd))
                return fd.CompareTo(vd);

            var fs = AsString(field);
            var vs = AsString(val);
            if (fs != null && vs != null)
                return string.Compare(fs, vs, StringComparison.OrdinalIgnoreCase);

            return null;
        }

        // Array membership (any element equals value) or, for a string field, substring.
        private static bool Contains(JsonElement field, JsonElement val)
        {
            if (field.ValueKind == JsonValueKind.Array)
            {
                foreach (var el in field.EnumerateArray())
                    if (ValueEquals(el, val)) return true;
                return false;
            }
            if (field.ValueKind == JsonValueKind.String)
            {
                var hay = field.GetString();
                var needle = AsString(val);
                if (hay == null || needle == null) return false;
                return hay.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0;
            }
            return false;
        }

        private static bool Like(JsonElement field, JsonElement val)
        {
            if (field.ValueKind != JsonValueKind.String) return false;
            var text = field.GetString();
            var pattern = AsString(val);
            if (text == null || pattern == null) return false;
            var rx = "^" + Regex.Escape(pattern).Replace("\\*", ".*").Replace("\\?", ".") + "$";
            return Regex.IsMatch(text, rx, RegexOptions.IgnoreCase | RegexOptions.Singleline);
        }

        private static bool TryAsDouble(JsonElement e, out double d)
        {
            switch (e.ValueKind)
            {
                case JsonValueKind.Number:
                    return e.TryGetDouble(out d);
                case JsonValueKind.String:
                    return double.TryParse(e.GetString(), NumberStyles.Any, CultureInfo.InvariantCulture, out d);
                default:
                    d = 0;
                    return false;
            }
        }

        private static string? AsString(JsonElement e)
        {
            switch (e.ValueKind)
            {
                case JsonValueKind.String:
                    return e.GetString();
                case JsonValueKind.Number:
                    return e.GetRawText();
                case JsonValueKind.True:
                    return "true";
                case JsonValueKind.False:
                    return "false";
                case JsonValueKind.Null:
                case JsonValueKind.Undefined:
                    return null;
                default:
                    return e.GetRawText();
            }
        }

        // ── rendering ─────────────────────────────────────────────────────────────
        private string BuildFailTable(List<JsonElement> failing)
        {
            var headers = _rule.FailTable;
            var shown = Math.Min(failing.Count, FailTableLimit);
            var rows = new List<IReadOnlyList<string>>(shown);
            for (int i = 0; i < shown; i++)
            {
                var row = failing[i];
                var cells = new string[headers.Count];
                for (int c = 0; c < headers.Count; c++)
                    cells[c] = TryGetField(row, headers[c], out var v) ? (AsString(v) ?? "") : "";
                rows.Add(cells);
            }

            var sb = new StringBuilder();
            sb.Append(Markdown.Table(headers, rows));
            var note = Markdown.TruncationNote(shown, failing.Count, "records");
            if (note.Length > 0)
            {
                sb.Append('\n');
                sb.Append(note);
            }
            return sb.ToString();
        }

        private static string Substitute(string text, Dictionary<string, string> tokens)
        {
            if (string.IsNullOrEmpty(text) || text.IndexOf('{') < 0) return text;
            foreach (var kv in tokens)
                text = text.Replace("{" + kv.Key + "}", kv.Value);
            return text;
        }

        private static string BuildResultDataJson(int matched, int satisfying, int failing, string mode, double threshold, double pct)
        {
            var buffer = new System.Buffers.ArrayBufferWriter<byte>();
            using (var w = new Utf8JsonWriter(buffer))
            {
                w.WriteStartObject();
                w.WriteNumber("matched", matched);
                w.WriteNumber("satisfying", satisfying);
                w.WriteNumber("failing", failing);
                w.WriteString("mode", mode);
                w.WriteNumber("threshold", threshold);
                w.WriteNumber("percent", pct);
                w.WriteEndObject();
            }
            return Encoding.UTF8.GetString(buffer.WrittenSpan);
        }
    }
}
