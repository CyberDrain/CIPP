using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Workload identities based on known networks are configured.
    /// Port of Invoke-CippTestZTNA21884. Skipped on no ConditionalAccessPolicies data. Passed when at
    /// least one enabled CA policy targets service principals and includes a location condition.
    /// </summary>
    public sealed class ZTNA21884 : ICippTest
    {
        public string Id => "ZTNA21884";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ConditionalAccessPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var workload = new List<JsonElement>();
            foreach (var p in Items(policies))
            {
                if (!StrEq(p, "state", "enabled")) continue;
                bool targetsWorkload = FlattenCount(p, "conditions", "clientApplications", "includeServicePrincipals") > 0;
                bool hasLocation = FlattenCount(p, "conditions", "locations", "includeLocations") > 0
                    || FlattenCount(p, "conditions", "locations", "excludeLocations") > 0;
                if (targetsWorkload && hasLocation) workload.Add(p);
            }

            var lines = new List<string>();
            if (workload.Count > 0)
            {
                lines.Add($"Found {workload.Count} enabled Conditional Access policy(s) protecting workload identities with location conditions.");
                lines.Add("");
                lines.Add("| Policy Name | State |");
                lines.Add("| :---------- | :---- |");
                for (int i = 0; i < workload.Count && i < 25; i++)
                    lines.Add($"| {Text(workload[i], "displayName")} | {Text(workload[i], "state")} |");
                return new CippTestResult(TestStatus.Passed, string.Join("\n", lines));
            }

            lines.Add("No enabled Conditional Access policies were found that target workload identities (service principals) and include a location condition.");
            lines.Add("");
            lines.Add("**Remediation:** Create a Conditional Access policy targeting service principals (`clientApplications.includeServicePrincipals`) with a trusted named-location condition. Requires Microsoft Entra Workload Identities license.");
            return new CippTestResult(TestStatus.Failed, string.Join("\n", lines));
        }
    }
}
