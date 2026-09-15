using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// All sign-in activity comes from managed devices.
    /// Port of Invoke-CippTestZTNA21892. Skipped on no ConditionalAccessPolicies data. Passed when at
    /// least one enabled CA policy applies to all users and all apps and requires a compliant or
    /// hybrid-joined device.
    /// </summary>
    public sealed class ZTNA21892 : ICippTest
    {
        public string Id => "ZTNA21892";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("ConditionalAccessPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped, "No Conditional Access policies found in cache.");

            // (policy, compliant, hybrid)
            var matching = new List<(JsonElement Policy, bool Compliant, bool Hybrid)>();
            foreach (var p in Items(policies))
            {
                bool allUsers = FlattenContains(p, "All", "conditions", "users", "includeUsers");
                bool allApps = FlattenContains(p, "All", "conditions", "applications", "includeApplications");
                bool compliant = FlattenContains(p, "compliantDevice", "grantControls", "builtInControls");
                bool hybrid = FlattenContains(p, "domainJoinedDevice", "grantControls", "builtInControls");
                bool enabled = StrEq(p, "state", "enabled");
                if (enabled && allUsers && allApps && (compliant || hybrid))
                    matching.Add((p, compliant, hybrid));
            }

            if (matching.Count == 0)
                return new CippTestResult(TestStatus.Failed,
                    "❌ **Fail**: No Conditional Access policies found that require managed devices for all sign-in activity.\n\n"
                    + "Organizations should enforce that all sign-ins come from managed devices (compliant or hybrid Azure AD joined) to ensure security controls are applied.");

            var sb = new StringBuilder("✅ **Pass**: Conditional Access policies require managed devices for all sign-in activity.\n\n");
            sb.Append("## Matching policies\n\n");
            sb.Append("| Policy name | State | All users | All apps | Compliant device | Hybrid joined |\n");
            sb.Append("| :---------- | :---- | :-------- | :------- | :--------------- | :------------ |\n");

            foreach (var m in matching)
            {
                var p = m.Policy;
                var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_ConditionalAccess/PolicyBlade/policyId/{Text(p, "id")}";
                var name = string.IsNullOrEmpty(Str(p, "displayName")) ? "Unnamed" : Str(p, "displayName");
                var compliant = m.Compliant ? "✅" : "❌";
                var hybrid = m.Hybrid ? "✅" : "❌";
                sb.Append($"| [{name}]({link}) | {Text(p, "state")} | ✅ | ✅ | {compliant} | {hybrid} |\n");
            }

            return new CippTestResult(TestStatus.Passed, sb.ToString());
        }
    }
}
