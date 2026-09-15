using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.6) — Identity Protection user risk policies SHALL be enabled.
    /// Port of Invoke-CippTestCIS_5_2_2_6. Any enabled CA policy with a non-empty userRiskLevels.
    /// </summary>
    public sealed class CIS_5_2_2_6 : ICippTest
    {
        public string Id => "CIS_5_2_2_6";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var ca = data.Get("ConditionalAccessPolicies");
            if (!Any(ca))
                return new CippTestResult(TestStatus.Skipped, "ConditionalAccessPolicies cache not found.");

            var matching = new List<JsonElement>();
            foreach (var p in ca.EnumerateArray())
            {
                if (StrEq(p, "state", "enabled") && Any(Path(p, "conditions", "userRiskLevels")))
                    matching.Add(p);
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} Conditional Access policy/policies act on user risk:\n\n");
                var lines = new List<string>();
                foreach (var m in matching)
                    lines.Add($"- {Str(m, "displayName")} (risk: {JoinLeafStrings(Path(m, "conditions", "userRiskLevels"), ", ")})");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy uses userRiskLevels. Create a policy that requires password change (or blocks) on High user risk.");
        }
    }
}
