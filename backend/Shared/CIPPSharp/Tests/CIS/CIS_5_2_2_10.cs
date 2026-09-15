using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.2.2.10) — A managed device SHALL be required to register security information.
    /// Port of Invoke-CippTestCIS_5_2_2_10. Single source: ConditionalAccessPolicies.
    /// </summary>
    public sealed class CIS_5_2_2_10 : ICippTest
    {
        public string Id => "CIS_5_2_2_10";

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
                if (!ContainsCI(PropPath(p, "conditions.applications.includeUserActions"), "urn:user:registersecurityinfo")) continue;

                var grant = PropPath(p, "grantControls");
                bool compliant = ContainsCI(PropPath(grant, "builtInControls"), "compliantDevice");
                bool domainJoined = ContainsCI(PropPath(grant, "builtInControls"), "domainJoinedDevice");
                bool locations = PsTruthy(PropPath(p, "conditions.locations"))
                                 && PsTruthy(PropPath(p, "conditions.locations.includeLocations"));

                if (compliant || domainJoined || locations) matching.Add(p);
            }

            if (matching.Count > 0)
            {
                var sb = new StringBuilder();
                sb.Append($"{matching.Count} Conditional Access policy/policies guard the Register security info user action:\n\n");
                var bullets = new List<string>();
                foreach (var p in matching) bullets.Add($"- {Str(p, "displayName")}");
                sb.Append(string.Join("\n", bullets));
                return new CippTestResult(TestStatus.Passed, sb.ToString());
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy targets the Register security info user action with a managed-device or trusted-location requirement.");
        }
    }
}
