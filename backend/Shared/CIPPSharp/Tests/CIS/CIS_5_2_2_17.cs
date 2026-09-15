using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.17) — Authentication transfer is blocked.
    /// Port of Invoke-CippTestCIS_5_2_2_17. Any enabled block policy for All users/apps whose
    /// authentication-flow transferMethods include 'authenticationTransfer'.
    /// </summary>
    public sealed class CIS_5_2_2_17 : ICippTest
    {
        public string Id => "CIS_5_2_2_17";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var ca = data.Get("ConditionalAccessPolicies");
            if (!Any(ca))
                return new CippTestResult(TestStatus.Skipped, "ConditionalAccessPolicies cache not found.");

            var matching = new List<JsonElement>();
            foreach (var p in ca.EnumerateArray())
            {
                if (StrEq(p, "state", "enabled")
                    && ArrContainsCI(Path(p, "conditions", "users", "includeUsers"), "All")
                    && ArrContainsCI(Path(p, "conditions", "applications", "includeApplications"), "All")
                    && PathTruthy(p, "conditions", "authenticationFlows")
                    && MatchCI(LeafStr(Path(p, "conditions", "authenticationFlows", "transferMethods")), "authenticationTransfer")
                    && ArrContainsCI(Path(p, "grantControls", "builtInControls"), "block"))
                {
                    matching.Add(p);
                }
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} Conditional Access policy/policies block authentication transfer:\n\n");
                var lines = new List<string>();
                foreach (var m in matching) lines.Add($"- {Str(m, "displayName")}");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy blocks the authenticationTransfer authentication flow for all users.");
        }
    }
}
