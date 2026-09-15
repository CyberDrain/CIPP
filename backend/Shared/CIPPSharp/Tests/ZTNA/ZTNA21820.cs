using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Activation alert for all privileged role assignments.
    /// Port of Invoke-CippTestZTNA21820. For each privileged role's PIM policy, fails on the first
    /// Notification_Requestor_EndUser_Assignment rule with default recipients enabled but no explicit
    /// recipients. NOTE (faithful to PS): a role with no PIM policy is listed as an issue but does NOT
    /// change the Passed status.
    /// </summary>
    public sealed class ZTNA21820 : ICippTest
    {
        public string Id => "ZTNA21820";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var privilegedRoles = PrivilegedRoles(data);
            if (privilegedRoles.Count == 0)
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = data.Get("RoleManagementPolicies");
            var policyByRoleId = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            foreach (var p in Items(policies))
            {
                var rdId = Str(p, "roleDefinitionId");
                if (StrEq(p, "scopeId", "/") && StrEq(p, "scopeType", "DirectoryRole") && rdId != null)
                    policyByRoleId[rdId] = p;
            }

            var issues = new List<(string Display, bool IsDefaultTrue, string Recipients)>();
            bool passed = true; // 'Passed'

            foreach (var role in privilegedRoles)
            {
                var tid = RoleTemplateId(role);
                var roleName = Str(role, "displayName") ?? "";
                if (tid == null || !policyByRoleId.TryGetValue(tid, out var policy))
                {
                    issues.Add((roleName, false, "N/A")); // No PIM policy assignment found
                    continue;
                }

                JsonElement rule = default;
                bool ruleFound = false;
                foreach (var r in Arr(policy, "effectiveRules"))
                    if (PropContains(r, "id", "Notification_Requestor_EndUser_Assignment")) { rule = r; ruleFound = true; break; }

                if (ruleFound)
                {
                    bool isDefaultTrue = IsTrue(rule, "isDefaultRecipientsEnabled");
                    int recipientCount = ArrayLen(rule, "notificationRecipients");
                    if (isDefaultTrue && recipientCount == 0)
                    {
                        passed = false;
                        issues.Add((roleName, true, "N/A"));
                        break;
                    }
                }
            }

            var sb = new StringBuilder(issues.Count == 0
                ? "Activation alerts are configured for privileged role assignments."
                : "Activation alerts are missing or improperly configured for privileged roles.");

            if (issues.Count > 0)
            {
                sb.Append("\n\n## Roles with missing or misconfigured alerts\n\n");
                sb.Append("| Role display name | Default recipients | Additional recipients |\n");
                sb.Append("| :---------------- | :----------------- | :------------------- |\n");
                const string roleLink = "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/RolesManagementMenuBlade/~/AllRoles";
                foreach (var i in issues)
                {
                    string defaultStatus = i.IsDefaultTrue ? "Enabled" : "Disabled";
                    sb.Append($"| [{i.Display}]({roleLink}) | {defaultStatus} | {i.Recipients} |\n");
                }
                sb.Append("\n\n*Not all misconfigured roles may be listed. For performance reasons, this assessment stops at the first detected issue.*\n");
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
