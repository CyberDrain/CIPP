using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// All privileged role assignments have a recipient that can receive notifications.
    /// Port of Invoke-CippTestZTNA21899. Skipped on no RoleManagementPolicies data. Fails when any PIM
    /// notification rule has an empty notificationRecipients collection.
    /// </summary>
    public sealed class ZTNA21899 : ICippTest
    {
        public string Id => "ZTNA21899";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("RoleManagementPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            int policyCount = policies.GetArrayLength();

            // (scopeType, scopeId, ruleId, level, type, recipientType)
            var missing = new List<(string ScopeType, string ScopeId, string RuleId, string Level, string Type, string RecipientType)>();
            foreach (var policy in Items(policies))
            {
                foreach (var rule in Arr(policy, "rules"))
                {
                    if (!StrEq(rule, "@odata.type", "#microsoft.graph.unifiedRoleManagementPolicyNotificationRule")) continue;
                    if (ArrayLen(rule, "notificationRecipients") == 0)
                        missing.Add((Text(policy, "scopeType"), Text(policy, "scopeId"), Text(rule, "id"),
                            Text(rule, "notificationLevel"), Text(rule, "notificationType"), Text(rule, "recipientType")));
                }
            }

            if (missing.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"All {policyCount} role management policy notification rule(s) have recipients configured.");

            var lines = new List<string>
            {
                $"{missing.Count} notification rule(s) across role management policies have no recipients configured.",
                "",
                "| Policy / Scope | Rule | Level | Type | Recipient Type |",
                "| :------------- | :--- | :---- | :--- | :------------- |"
            };

            for (int i = 0; i < missing.Count && i < 25; i++)
            {
                var m = missing[i];
                lines.Add($"| {m.ScopeType}:{m.ScopeId} | {m.RuleId} | {m.Level} | {m.Type} | {m.RecipientType} |");
            }

            if (missing.Count > 25)
            {
                lines.Add("");
                lines.Add($"...and {missing.Count - 25} more.");
            }

            lines.Add("");
            lines.Add("**Remediation:** Add at least one notification recipient (admin, requestor, or approver group) to each PIM notification rule so role activations and approvals raise alerts.");

            return new CippTestResult(TestStatus.Failed, string.Join("\n", lines));
        }
    }
}
