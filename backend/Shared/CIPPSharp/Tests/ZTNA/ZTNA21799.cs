using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Restrict high risk sign-ins (Block high risk sign-ins).
    /// Port of Invoke-CippTestZTNA21799. When any authentication method is enabled the acceptable
    /// controls are block/mfa/authenticationStrength; otherwise only block counts. A matching enabled
    /// CA policy targeting All users on high sign-in risk must exist.
    /// </summary>
    public sealed class ZTNA21799 : ICippTest
    {
        public string Id => "ZTNA21799";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var authMethods = data.Get("AuthenticationMethodsPolicy");
            var caPolicies = data.Get("ConditionalAccessPolicies");

            if (!Any(caPolicies) || !Any(authMethods))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            // ($authMethodPolicy.authenticationMethodConfigurations.state -eq 'enabled').count -gt 0
            bool anyMethodEnabled = false;
            foreach (var rec in Items(authMethods))
                foreach (var m in Arr(rec, "authenticationMethodConfigurations"))
                    if (StrEq(m, "state", "enabled")) { anyMethodEnabled = true; break; }

            var matched = new List<JsonElement>();
            foreach (var p in Items(caPolicies))
            {
                bool high = FlattenContains(p, "high", "conditions", "signInRiskLevels");
                bool allUsers = FlattenContains(p, "All", "conditions", "users", "includeUsers");
                bool enabled = StrEq(p, "state", "enabled");
                if (!high || !allUsers || !enabled) continue;

                bool hasBlock = FlattenContains(p, "block", "grantControls", "builtInControls");
                bool hasMfa = FlattenContains(p, "mfa", "grantControls", "builtInControls");
                var authStrength = Nested(p, "grantControls", "authenticationStrength");
                bool hasAuthStrength = authStrength.ValueKind != JsonValueKind.Undefined && authStrength.ValueKind != JsonValueKind.Null;

                bool controlOk = anyMethodEnabled ? (hasBlock || hasMfa || hasAuthStrength) : hasBlock;
                if (controlOk) matched.Add(p);
            }

            bool passed = matched.Count > 0;
            var text = passed
                ? "All high-risk sign-in attempts are mitigated by Conditional Access policies enforcing appropriate controls."
                : "Some high-risk sign-in attempts are not adequately mitigated by Conditional Access policies.";

            var sb = new StringBuilder(text);
            if (matched.Count > 0)
            {
                sb.Append("\n## Conditional Access Policies targeting high-risk sign-in attempts\n\n");
                sb.Append("| Policy Name | Grant Controls | Target Users |\n");
                sb.Append("| :---------- | :------------- | :----------- |\n");
                foreach (var p in matched)
                {
                    // PS switch has no break: later matches win (block < mfa < authStrength).
                    string grant = "";
                    if (FlattenContains(p, "block", "grantControls", "builtInControls")) grant = "Block Access";
                    if (FlattenContains(p, "mfa", "grantControls", "builtInControls")) grant = "Require Multi-Factor Authentication";
                    var authStrength = Nested(p, "grantControls", "authenticationStrength");
                    if (authStrength.ValueKind != JsonValueKind.Undefined && authStrength.ValueKind != JsonValueKind.Null)
                        grant = "Require Authentication Strength";

                    var users = FlattenStrings(p, "conditions", "users", "includeUsers");
                    string target = users.Contains("All") ? "All Users" : string.Join(", ", users);
                    sb.Append($"| {Text(p, "displayName")} | {grant} | {target} |\n");
                }
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
