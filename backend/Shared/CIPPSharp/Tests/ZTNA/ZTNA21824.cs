using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Guests don't have long lived sign-in sessions.
    /// Port of Invoke-CippTestZTNA21824. Every enabled/report-only CA policy that targets guests
    /// (and has no terms-of-use control) must enforce a short sign-in frequency.
    /// </summary>
    public sealed class ZTNA21824 : ICippTest
    {
        public string Id => "ZTNA21824";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var caPolicies = data.Get("ConditionalAccessPolicies");
            if (!Any(caPolicies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var filtered = new List<JsonElement>();
            foreach (var p in Items(caPolicies))
            {
                var guests = Nested(p, "conditions", "users", "includeGuestsOrExternalUsers");
                bool hasGuests = guests.ValueKind != JsonValueKind.Undefined && guests.ValueKind != JsonValueKind.Null;
                if (!hasGuests) continue;

                if (!(StrEq(p, "state", "enabled") || StrEq(p, "state", "enabledForReportingButNotEnforced"))) continue;

                var tou = Nested(p, "grantControls", "termsOfUse");
                bool touOk = tou.ValueKind == JsonValueKind.Undefined || tou.ValueKind == JsonValueKind.Null
                    || (tou.ValueKind == JsonValueKind.Array && tou.GetArrayLength() == 0);
                if (!touOk) continue;

                filtered.Add(p);
            }

            var matchedIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var p in filtered)
            {
                if (IsShortSession(p))
                {
                    var id = Str(p, "id");
                    if (id != null) matchedIds.Add(id);
                }
            }

            bool passed = filtered.Count == matchedIds.Count;
            var text = passed
                ? "Guests don't have long lived sign-in sessions."
                : "Guests do have long lived sign-in sessions.";

            var sb = new StringBuilder(text);
            if (filtered.Count > 0)
            {
                sb.Append("\n## Sign-in frequency policies\n\n");
                sb.Append("| Policy Name | Sign-in Frequency | Status |\n");
                sb.Append("| :---------- | :---------------- | :----- |\n");
                foreach (var p in filtered)
                {
                    var sif = Nested(p, "sessionControls", "signInFrequency");
                    var type = Str(sif, "type");
                    string freq;
                    if (string.Equals(type, "hours", StringComparison.OrdinalIgnoreCase)) freq = $"{ValueText(sif)} hours";
                    else if (string.Equals(type, "days", StringComparison.OrdinalIgnoreCase)) freq = $"{ValueText(sif)} days";
                    else freq = string.Equals(Str(sif, "frequencyInterval"), "everyTime", StringComparison.OrdinalIgnoreCase) ? "Every time" : "Not configured";

                    var id = Str(p, "id");
                    string status = id != null && matchedIds.Contains(id) ? "✅" : "❌";
                    sb.Append($"| {Text(p, "displayName")} | {freq} | {status} |\n");
                }
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }

        private static bool IsShortSession(JsonElement policy)
        {
            var sif = Nested(policy, "sessionControls", "signInFrequency");
            if (sif.ValueKind == JsonValueKind.Undefined || sif.ValueKind == JsonValueKind.Null) return false;
            if (!IsTrue(sif, "isEnabled")) return false;

            var typeEl = Prop(sif, "type");
            var type = typeEl.ValueKind == JsonValueKind.Null || typeEl.ValueKind == JsonValueKind.Undefined ? null : AsString(typeEl);
            bool typeIsNull = type == null;

            double value = 0;
            bool hasValue = TryDouble(Prop(sif, "value"), out value);

            if (string.Equals(type, "hours", StringComparison.OrdinalIgnoreCase) && hasValue && value <= 24) return true;
            if (string.Equals(type, "days", StringComparison.OrdinalIgnoreCase) && hasValue && value == 1) return true;
            if (typeIsNull && string.Equals(Str(sif, "frequencyInterval"), "everyTime", StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        private static bool TryDouble(JsonElement v, out double d)
        {
            d = 0;
            if (v.ValueKind == JsonValueKind.Number && v.TryGetDouble(out d)) return true;
            if (v.ValueKind == JsonValueKind.String && double.TryParse(v.GetString(), System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out d)) return true;
            return false;
        }

        private static string ValueText(JsonElement sif) => Cell(Prop(sif, "value"));
    }
}
