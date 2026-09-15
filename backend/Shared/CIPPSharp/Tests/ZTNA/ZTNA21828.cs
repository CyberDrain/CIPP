using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Authentication transfer is blocked.
    /// Port of Invoke-CippTestZTNA21828. An enabled CA policy targeting all users and all applications
    /// must block the authenticationTransfer flow.
    /// </summary>
    public sealed class ZTNA21828 : ICippTest
    {
        public string Id => "ZTNA21828";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var caPolicies = data.Get("ConditionalAccessPolicies");
            if (!Any(caPolicies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var matched = new List<JsonElement>();
            foreach (var p in Items(caPolicies))
            {
                var transfer = NestedStr(p, "conditions", "authenticationFlows", "transferMethods");
                bool hasAuthTransfer = transfer != null && transfer.IndexOf("authenticationTransfer", StringComparison.OrdinalIgnoreCase) >= 0;
                if (hasAuthTransfer
                    && FlattenContains(p, "block", "grantControls", "builtInControls")
                    && FlattenContains(p, "all", "conditions", "users", "includeUsers")
                    && FlattenContains(p, "all", "conditions", "applications", "includeApplications")
                    && StrEq(p, "state", "enabled"))
                    matched.Add(p);
            }

            bool passed = matched.Count > 0;
            var text = passed
                ? "Authentication transfer is blocked by Conditional Access Policy(s)."
                : "Authentication transfer is not blocked.";

            var sb = new StringBuilder(text);
            if (matched.Count > 0)
            {
                sb.Append("\n## Conditional Access Policies targeting Authentication Transfer\n\n");
                sb.Append("| Policy Name | Policy ID | State | Created | Modified |\n");
                sb.Append("| :---------- | :-------- | :---- | :------ | :------- |\n");
                foreach (var p in matched)
                {
                    string created = Str(p, "createdDateTime") ?? "N/A";
                    string modified = Str(p, "modifiedDateTime") ?? "N/A";
                    sb.Append($"| {Text(p, "displayName")} | {Text(p, "id")} | {Text(p, "state")} | {created} | {modified} |\n");
                }
            }
            else
            {
                sb.Append("\n\nNo Conditional Access policies targeting authentication transfer.");
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
