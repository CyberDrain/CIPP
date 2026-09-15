using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Global Administrator role activation triggers an approval workflow.
    /// Port of Invoke-CippTestZTNA21817. The GA PIM policy's Approval_EndUser_Assignment rule must
    /// require approval and have at least one primary approver configured.
    /// </summary>
    public sealed class ZTNA21817 : ICippTest
    {
        private const string GlobalAdminRoleId = "62e90394-69f5-4237-9190-012177145e10";

        public string Id => "ZTNA21817";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var policies = data.Get("RoleManagementPolicies");
            if (!Any(policies))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var gaPolicies = new List<JsonElement>();
            foreach (var p in Items(policies))
                if (StrEq(p, "scopeId", "/") && StrEq(p, "scopeType", "DirectoryRole") && StrEq(p, "roleDefinitionId", GlobalAdminRoleId))
                    gaPolicies.Add(p);

            bool result = false;
            string tableRows;
            string prefix;

            if (gaPolicies.Count > 0)
            {
                var approvalRules = new List<JsonElement>();
                foreach (var p in gaPolicies)
                    foreach (var rule in Arr(p, "rules"))
                        if (PropContains(rule, "id", "Approval_EndUser_Assignment")) approvalRules.Add(rule);

                bool approvalRequired = false;
                foreach (var rule in approvalRules)
                    if (NestedTrue(rule, "setting", "isApprovalRequired")) { approvalRequired = true; break; }

                if (approvalRules.Count > 0 && approvalRequired)
                {
                    int approverCount = 0;
                    foreach (var rule in approvalRules)
                        foreach (var stage in Arr(Nested(rule, "setting"), "approvalStages"))
                            approverCount += ArrayLen(stage, "primaryApprovers");

                    if (approverCount > 0)
                    {
                        result = true;
                        string primary = "", escalation = "";
                        var firstStages = Arr(Nested(approvalRules[0], "setting"), "approvalStages").GetEnumerator();
                        if (firstStages.MoveNext())
                        {
                            var stage0 = firstStages.Current;
                            primary = JoinDescriptions(stage0, "primaryApprovers");
                            escalation = JoinDescriptions(stage0, "escalationApprovers");
                        }
                        prefix = $"✅ **Pass**: Approval required with {approverCount} primary approver(s) configured.";
                        tableRows = $"| Yes | {primary} | {escalation} |\n";
                    }
                    else
                    {
                        prefix = "❌ **Fail**: Approval required but no approvers configured.";
                        tableRows = "| Yes | None | None |\n";
                    }
                }
                else
                {
                    prefix = "❌ **Fail**: Approval not required for Global Administrator role activation.";
                    tableRows = "| No | N/A | N/A |\n";
                }
            }
            else
            {
                prefix = "❌ **Fail**: No PIM policy found for Global Administrator role.";
                tableRows = "| N/A | N/A | N/A |\n";
            }

            var md = new StringBuilder(prefix);
            md.Append("\n\n## Global Administrator role activation and approval workflow\n\n\n");
            md.Append("| Approval Required | Primary Approvers | Escalation Approvers |\n");
            md.Append("| :---------------- | :---------------- | :------------------- |\n");
            md.Append(tableRows);

            return new CippTestResult(result ? TestStatus.Passed : TestStatus.Failed, md.ToString());
        }

        private static string JoinDescriptions(JsonElement stage, string name)
        {
            var parts = new List<string>();
            foreach (var a in Arr(stage, name))
            {
                var d = Str(a, "description");
                if (d != null) parts.Add(d);
            }
            return string.Join(", ", parts);
        }
    }
}
