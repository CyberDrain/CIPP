using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Secure the MFA registration (My Security Info) page.
    /// Port of Invoke-CippTestZTNA21806. An enabled CA policy targeting the registersecurityinfo user
    /// action for All users must exist.
    /// </summary>
    public sealed class ZTNA21806 : ICippTest
    {
        public string Id => "ZTNA21806";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var caPolicies = data.Get("ConditionalAccessPolicies");
            if (!Any(caPolicies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var matched = new List<JsonElement>();
            foreach (var p in Items(caPolicies))
            {
                if (FlattenContains(p, "urn:user:registersecurityinfo", "conditions", "applications", "includeUserActions")
                    && FlattenContains(p, "All", "conditions", "users", "includeUsers")
                    && StrEq(p, "state", "enabled"))
                    matched.Add(p);
            }

            bool passed = matched.Count > 0;
            var text = passed
                ? "Security information registration is protected by Conditional Access policies."
                : "Security information registration is not protected by Conditional Access policies.";

            var sb = new StringBuilder(text);
            if (matched.Count > 0)
            {
                sb.Append("\n## Conditional Access Policies targeting security information registration\n\n");
                sb.Append("| Policy Name | User Actions Targeted | Grant Controls Applied |\n");
                sb.Append("| :---------- | :-------------------- | :--------------------- |\n");
                foreach (var p in matched)
                {
                    var actions = string.Join("", FlattenStrings(p, "conditions", "applications", "includeUserActions"));
                    var controls = string.Join(", ", FlattenStrings(p, "grantControls", "builtInControls"));
                    sb.Append($"| {Text(p, "displayName")} | {actions} | {controls} |\n");
                }
            }
            else
            {
                sb.Append("No Conditional Access policies targeting security information registration.");
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
