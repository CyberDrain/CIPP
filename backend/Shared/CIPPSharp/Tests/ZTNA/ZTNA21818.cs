using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Privileged role activations have monitoring and alerting configured.
    /// Port of Invoke-CippTestZTNA21818. Walks each privileged role's PIM policy notification rules;
    /// fails on the first rule with default recipients enabled but no additional recipients (the PS
    /// check stops at the first offender).
    /// </summary>
    public sealed class ZTNA21818 : ICippTest
    {
        public string Id => "ZTNA21818";

        private static readonly (string RuleId, string Scenario, string Type)[] Notifications =
        {
            ("Notification_Admin_Admin_Eligibility", "Send notifications when members are assigned as eligible to this role", "Role assignment alert"),
            ("Notification_Requestor_Admin_Eligibility", "Send notifications when members are assigned as eligible to this role", "Notification to the assigned user (assignee)"),
            ("Notification_Approver_Admin_Eligibility", "Send notifications when members are assigned as eligible to this role", "Request to approve a role assignment renewal/extension"),
            ("Notification_Admin_Admin_Assignment", "Send notifications when members are assigned as active to this role", "Role assignment alert"),
            ("Notification_Requestor_Admin_Assignment", "Send notifications when members are assigned as active to this role", "Notification to the assigned user (assignee)"),
            ("Notification_Approver_Admin_Assignment", "Send notifications when members are assigned as active to this role", "Request to approve a role assignment renewal/extension"),
            ("Notification_Admin_EndUser_Assignment", "Send notifications when eligible members activate this role", "Role activation alert"),
            ("Notification_Requestor_EndUser_Assignment", "Send notifications when eligible members activate this role", "Notification to activated user (requestor)"),
            ("Notification_Approver_EndUser_Assignment", "Send notifications when eligible members activate this role", "Request to approve an activation"),
        };

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var privilegedRoles = PrivilegedRoles(data);
            var policies = data.Get("RoleManagementPolicies");

            var gathered = new List<(string RoleName, string Scenario, string Type, string DefaultEnabled, string Recipients)>();
            bool passed = true;
            bool exit = false;

            foreach (var role in privilegedRoles)
            {
                var tid = RoleTemplateId(role);
                if (tid == null) continue;
                var roleName = Str(role, "displayName") ?? "";

                JsonElement policy = default;
                bool found = false;
                foreach (var p in Items(policies))
                    if (StrEq(p, "scopeId", "/") && StrEq(p, "scopeType", "DirectoryRole") && StrEq(p, "roleDefinitionId", tid))
                    { policy = p; found = true; break; }
                if (!found) continue;

                foreach (var n in Notifications)
                {
                    JsonElement rule = default;
                    bool ruleFound = false;
                    foreach (var r in Arr(policy, "rules"))
                        if (StrEq(r, "id", n.RuleId)) { rule = r; ruleFound = true; break; }
                    if (!ruleFound) continue;

                    bool defaultEnabled = IsTrue(rule, "isDefaultRecipientsEnabled");
                    var recipients = new List<string>();
                    foreach (var rec in Arr(rule, "notificationRecipients")) { var s = AsString(rec); if (s != null) recipients.Add(s); }

                    gathered.Add((roleName, n.Scenario, n.Type,
                        Cell(Prop(rule, "isDefaultRecipientsEnabled")),
                        recipients.Count > 0 ? string.Join(", ", recipients) : ""));

                    if (defaultEnabled && recipients.Count == 0) { passed = false; exit = true; break; }
                }
                if (exit) break;
            }

            var sb = new StringBuilder(passed
                ? "Role notifications are properly configured for privileged role.\n\n"
                : "Role notifications are not properly configured.\n\nNote: To save time, this check stops when it finds the first role that does not have notifications. After fixing this role and all other roles, we recommend running the check again to verify.\n\n");

            sb.Append("## Notifications for high privileged roles\n\n");
            sb.Append("| Role Name | Notification Scenario | Notification Type | Default Recipients Enabled | Additional Recipients |\n");
            sb.Append("| :-------- | :-------------------- | :---------------- | :------------------------- | :-------------------- |\n");
            foreach (var g in gathered)
                sb.Append($"| {g.RoleName} | {g.Scenario} | {g.Type} | {g.DefaultEnabled} | {g.Recipients} |\n");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
