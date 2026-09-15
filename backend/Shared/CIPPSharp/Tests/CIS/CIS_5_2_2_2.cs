using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.2) — MFA SHALL be enabled for all users.
    /// Port of Invoke-CippTestCIS_5_2_2_2. Any enabled CA policy that targets All users + All cloud
    /// apps and requires MFA (built-in control 'mfa' or an authentication strength).
    /// </summary>
    public sealed class CIS_5_2_2_2 : ICippTest
    {
        public string Id => "CIS_5_2_2_2";

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
                    && ArrContainsCI(Path(p, "conditions", "users", "includeUsers"), "All")
                    && PathTruthy(p, "grantControls")
                    && (ArrContainsCI(Path(p, "grantControls", "builtInControls"), "mfa")
                        || PathTruthy(p, "grantControls", "authenticationStrength"))
                    && ArrContainsCI(Path(p, "conditions", "applications", "includeApplications"), "All"))
                {
                    matching.Add(p);
                }
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} Conditional Access policy/policies require MFA for all users on all cloud apps:\n\n");
                var lines = new List<string>();
                foreach (var m in matching) lines.Add($"- {Str(m, "displayName")}");
                sb.Append(string.Join("\n", lines));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy targets All users / All cloud apps with MFA.");
        }
    }
}
