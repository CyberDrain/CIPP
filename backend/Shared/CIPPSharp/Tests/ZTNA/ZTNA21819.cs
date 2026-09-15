using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Activation alert for Global Administrator role assignment.
    /// Port of Invoke-CippTestZTNA21819. The GA PIM policy's Notification_Requestor_EndUser_Assignment
    /// effective rule must have default recipients enabled or explicit recipients.
    /// </summary>
    public sealed class ZTNA21819 : ICippTest
    {
        private const string GlobalAdminRoleId = "62e90394-69f5-4237-9190-012177145e10";

        public string Id => "ZTNA21819";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var roles = data.Get("Roles");
            JsonElement gaRole = default;
            bool gaFound = false;
            foreach (var r in Items(roles))
                if (StrEq(r, "roleTemplateId", GlobalAdminRoleId)) { gaRole = r; gaFound = true; break; }

            if (!gaFound)
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var policies = data.Get("RoleManagementPolicies");
            JsonElement policy = default;
            bool policyFound = false;
            foreach (var p in Items(policies))
                if (StrEq(p, "scopeId", "/") && StrEq(p, "scopeType", "DirectoryRole") && StrEq(p, "roleDefinitionId", GlobalAdminRoleId))
                { policy = p; policyFound = true; break; }

            bool passed = false;
            JsonElement isDefaultEnabled = default;
            var recipients = new List<string>();

            if (policyFound)
            {
                JsonElement rule = default;
                bool ruleFound = false;
                foreach (var r in Arr(policy, "effectiveRules"))
                    if (PropContains(r, "id", "Notification_Requestor_EndUser_Assignment")) { rule = r; ruleFound = true; break; }

                if (ruleFound)
                {
                    isDefaultEnabled = Prop(rule, "isDefaultRecipientsEnabled");
                    foreach (var rec in Arr(rule, "notificationRecipients")) { var s = AsString(rec); if (s != null) recipients.Add(s); }
                    bool defaultTrue = isDefaultEnabled.ValueKind == JsonValueKind.True;
                    if (recipients.Count > 0 || defaultTrue) passed = true;
                }
            }

            var sb = new StringBuilder(passed
                ? "Activation alerts are configured for Global Administrator role.\n\n"
                : "Activation alerts are missing or improperly configured for Global Administrator role.\n\n");
            sb.Append("| Role display name | Default recipients | Additional recipients |\n");
            sb.Append("| :---------------- | :----------------- | :------------------- |\n");

            const string roleLink = "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/RolesManagementMenuBlade/~/AllRoles";
            string displayNameLink = $"[{Text(gaRole, "displayName")}]({roleLink})";
            string defaultStatus = isDefaultEnabled.ValueKind == JsonValueKind.True ? "✅ Enabled"
                : (isDefaultEnabled.ValueKind == JsonValueKind.False ? "❌ Disabled" : "N/A");
            string recipientsDisplay = recipients.Count > 0 ? string.Join(", ", recipients) : "-";
            sb.Append($"| {displayNameLink} | {defaultStatus} | {recipientsDisplay} |\n");

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
