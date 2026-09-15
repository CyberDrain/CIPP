using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Workload identities configured with risk-based policies.
    /// Port of Invoke-CippTestZTNA21883. Skipped on no ConditionalAccessPolicies data. Passed when at
    /// least one enabled CA policy blocks authentication and targets service principals.
    /// </summary>
    public sealed class ZTNA21883 : ICippTest
    {
        public string Id => "ZTNA21883";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ConditionalAccessPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped, "No Conditional Access policies found in cache.");

            var matched = new List<JsonElement>();
            foreach (var p in Items(policies))
            {
                bool blocksAuth = FlattenContains(p, "block", "grantControls", "builtInControls");
                bool includesSp = FlattenCount(p, "conditions", "clientApplications", "includeServicePrincipals") > 0;
                bool enabled = StrEq(p, "state", "enabled");
                if (blocksAuth && includesSp && enabled) matched.Add(p);
            }

            if (matched.Count == 0)
                return new CippTestResult(TestStatus.Failed,
                    "❌ **Fail**: No Conditional Access policies found that protect workload identities with risk-based controls.\n\n"
                    + "Workload identities should be protected by policies that block authentication when service principal risk is detected.");

            var sb = new StringBuilder("✅ **Pass**: Workload identities are protected by risk-based Conditional Access policies.\n\n");
            sb.Append("## Matching policies\n\n");
            sb.Append("| Policy name | State | Service principals | Grant controls |\n");
            sb.Append("| :---------- | :---- | :----------------- | :------------- |\n");

            foreach (var p in matched)
            {
                var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/{Text(p, "id")}";
                var name = string.IsNullOrEmpty(Str(p, "displayName")) ? "Unnamed" : Str(p, "displayName");

                var spList = FlattenStrings(p, "conditions", "clientApplications", "includeServicePrincipals");
                string spTargets;
                if (spList.Count > 0)
                {
                    spTargets = string.Join(", ", spList.GetRange(0, System.Math.Min(3, spList.Count)));
                    if (spList.Count > 3) spTargets += $" (and {spList.Count - 3} more)";
                }
                else spTargets = "None";

                var controls = FlattenStrings(p, "grantControls", "builtInControls");
                var grants = controls.Count > 0 ? string.Join(", ", controls) : "None";

                sb.Append($"| [{name}]({link}) | {Text(p, "state")} | {spTargets} | {grants} |\n");
            }

            return new CippTestResult(TestStatus.Passed, sb.ToString());
        }
    }
}
