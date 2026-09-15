using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.11) — Sign-in frequency for Intune Enrollment SHALL be 'Every time'. Port of
    /// Invoke-CippTestCIS_5_2_2_11. Single source: ConditionalAccessPolicies.
    /// </summary>
    public sealed class CIS_5_2_2_11 : ICippTest
    {
        public string Id => "CIS_5_2_2_11";

        private const string IntuneEnrollmentApp = "d4ebce55-015a-49b5-a083-c84d1797ae8c";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var ca = data.Get("ConditionalAccessPolicies");
            if (!Any(ca))
            {
                return new CippTestResult(TestStatus.Skipped, "ConditionalAccessPolicies cache not found.");
            }

            var matching = new List<JsonElement>();
            foreach (var p in ca.EnumerateArray())
            {
                if (!StrEq(p, "state", "enabled")) continue;
                if (!ContainsCI(PropPath(p, "conditions.applications.includeApplications"), IntuneEnrollmentApp)) continue;

                if (!PsTruthy(PropPath(p, "sessionControls"))) continue;
                var sif = PropPath(p, "sessionControls.signInFrequency");
                if (!PsTruthy(sif)) continue;
                if (!StrEq(sif, "frequencyInterval", "everyTime")) continue;

                matching.Add(p);
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} Conditional Access policy/policies require sign-in every time for Intune Enrollment:\n\n");
                var bullets = new List<string>();
                foreach (var p in matching) bullets.Add($"- {Str(p, "displayName")}");
                sb.Append(string.Join("\n", bullets));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy targets Microsoft Intune Enrollment with sign-in frequency Every time.");
        }
    }
}
