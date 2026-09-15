using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (3.2.2) — DLP policies SHALL be enabled for Microsoft Teams. Port of
    /// Invoke-CippTestCIS_3_2_2. Single source: DlpCompliancePolicies. Passed when at least one
    /// enforced policy covers Teams (TeamsLocation / Workload matches Teams / TeamsLocationException).
    /// </summary>
    public sealed class CIS_3_2_2 : ICippTest
    {
        public string Id => "CIS_3_2_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var dlp = data.Get("DlpCompliancePolicies");
            if (!Any(dlp))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "DlpCompliancePolicies cache not found. Please refresh the cache for this tenant.");
            }

            var teams = new List<JsonElement>();
            foreach (var p in dlp.EnumerateArray())
            {
                if (StrEq(p, "Mode", "Enable") && BoolEq(p, "Enabled", true)
                    && (PsTruthyProp(p, "TeamsLocation")
                        || MatchAny(Prop(p, "Workload"), "Teams")
                        || PsTruthyProp(p, "TeamsLocationException")))
                {
                    teams.Add(p);
                }
            }

            if (teams.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{teams.Count} DLP policy/policies cover Microsoft Teams:\n\n");
                var bullets = new List<string>();
                foreach (var p in teams) bullets.Add($"- {Str(p, "Name")}");
                sb.Append(string.Join("\n", bullets));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled DLP policy currently covers Microsoft Teams. Add Teams to the locations of at least one enforced DLP policy.");
        }
    }
}
