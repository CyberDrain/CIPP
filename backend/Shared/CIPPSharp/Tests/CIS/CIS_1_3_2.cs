using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (1.3.2) — Idle session timeout SHALL be 3 hours or less for unmanaged devices.
    /// Port of Invoke-CippTestCIS_1_3_2. Looks for an enabled CA policy whose sign-in frequency
    /// enforces &lt;= 3 hours (or 0 days).
    /// </summary>
    public sealed class CIS_1_3_2 : ICippTest
    {
        public string Id => "CIS_1_3_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ConditionalAccessPolicies");
            if (!Any(policies))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "ConditionalAccessPolicies cache not found. Please refresh the cache for this tenant.");
            }

            var matching = new List<JsonElement>();
            foreach (var p in policies.EnumerateArray())
            {
                if (!StrEq(p, "state", "enabled")) continue;
                if (!TryProp(p, "sessionControls", out var sc) || sc.ValueKind != JsonValueKind.Object) continue;
                if (!TryProp(sc, "signInFrequency", out var sif) || sif.ValueKind != JsonValueKind.Object) continue;
                if (!IsTrue(sif, "isEnabled")) continue;

                long val = Int(sif, "value");
                bool hours = StrEq(sif, "type", "hours") && val <= 3;
                bool days = StrEq(sif, "type", "days") && val == 0;
                if (hours || days) matching.Add(p);
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} Conditional Access policy/policies enforce sign-in frequency of 3 hours or less:\n\n");
                var lines = new List<string>();
                foreach (var p in matching) lines.Add($"- {Str(p, "displayName")}");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy enforces a sign-in frequency of 3 hours or less. Create a CA policy targeting unmanaged devices with signInFrequency configured.");
        }
    }
}
