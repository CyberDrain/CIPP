using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (3.2.3) — DLP policies SHALL be published for Copilot users. Port of
    /// Invoke-CippTestCIS_3_2_3. Single source: DlpCompliancePolicies. Passed when at least one
    /// enforced policy covers Copilot (EnforcementPlanes matches CopilotExperiences / Workload Copilot).
    /// </summary>
    public sealed class CIS_3_2_3 : ICippTest
    {
        public string Id => "CIS_3_2_3";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var dlp = data.Get("DlpCompliancePolicies");
            if (!Any(dlp))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "DlpCompliancePolicies cache not found. Please refresh the cache for this tenant.");
            }

            var copilot = new List<JsonElement>();
            foreach (var p in dlp.EnumerateArray())
            {
                if (StrEq(p, "Mode", "Enable") && BoolEq(p, "Enabled", true)
                    && (MatchAny(Prop(p, "EnforcementPlanes"), "CopilotExperiences")
                        || MatchAny(Prop(p, "Workload"), "Copilot")))
                {
                    copilot.Add(p);
                }
            }

            if (copilot.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{copilot.Count} DLP policy/policies cover Microsoft 365 Copilot:\n\n");
                var bullets = new List<string>();
                foreach (var p in copilot) bullets.Add($"- {Str(p, "Name")}");
                sb.Append(string.Join("\n", bullets));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled DLP policy currently covers Microsoft 365 Copilot. Add the Microsoft 365 Copilot and Copilot Chat location to at least one enforced DLP policy.");
        }
    }
}
