using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.12) — The device code sign-in flow SHALL be blocked. Port of
    /// Invoke-CippTestCIS_5_2_2_12. Single source: ConditionalAccessPolicies.
    /// </summary>
    public sealed class CIS_5_2_2_12 : ICippTest
    {
        public string Id => "CIS_5_2_2_12";

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

                var flows = PropPath(p, "conditions.authenticationFlows");
                if (!PsTruthy(flows)) continue;
                if (!MatchAny(PropPath(flows, "transferMethods"), "deviceCodeFlow")) continue;
                if (!ContainsCI(PropPath(p, "grantControls.builtInControls"), "block")) continue;

                matching.Add(p);
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} Conditional Access policy/policies block the device code flow:\n\n");
                var bullets = new List<string>();
                foreach (var p in matching) bullets.Add($"- {Str(p, "displayName")}");
                sb.Append(string.Join("\n", bullets));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy blocks the deviceCodeFlow authentication flow.");
        }
    }
}
