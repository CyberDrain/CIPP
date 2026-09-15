using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.3) — Conditional Access policies SHALL block legacy authentication.
    /// Port of Invoke-CippTestCIS_5_2_2_3. Any enabled CA policy with a Block grant that targets a
    /// legacy client app type (exchangeActiveSync / other).
    /// </summary>
    public sealed class CIS_5_2_2_3 : ICippTest
    {
        public string Id => "CIS_5_2_2_3";

        private static readonly HashSet<string> LegacyClients =
            new(StringComparer.OrdinalIgnoreCase) { "exchangeActiveSync", "other" };

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var ca = data.Get("ConditionalAccessPolicies");
            if (!Any(ca))
                return new CippTestResult(TestStatus.Skipped,
                    "ConditionalAccessPolicies cache not found. Please refresh the cache for this tenant.");

            var matching = new List<JsonElement>();
            foreach (var p in ca.EnumerateArray())
            {
                if (StrEq(p, "state", "enabled")
                    && ArrContainsCI(Path(p, "grantControls", "builtInControls"), "block")
                    && PathTruthy(p, "conditions", "clientAppTypes")
                    && AnyStringInSet(Path(p, "conditions", "clientAppTypes"), LegacyClients))
                {
                    matching.Add(p);
                }
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} Conditional Access policy/policies block legacy authentication:\n\n");
                var lines = new List<string>();
                foreach (var m in matching) lines.Add($"- {Str(m, "displayName")}");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy targets legacy authentication client app types with a Block grant.");
        }
    }
}
