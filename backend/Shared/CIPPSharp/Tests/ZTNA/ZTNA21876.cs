using System;
using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Use PIM for Microsoft Entra privileged roles.
    /// Port of Invoke-CippTestZTNA21876. Skipped on no RoleAssignmentScheduleInstances data. Failed
    /// when any standing (assignmentType 'Assigned', Direct/Group member) assignment targets a
    /// privileged role. Uses the test's own privileged-role template-id list (verbatim from the PS).
    /// </summary>
    public sealed class ZTNA21876 : ICippTest
    {
        public string Id => "ZTNA21876";

        private static readonly HashSet<string> PrivilegedRoleTemplateIds = new(StringComparer.OrdinalIgnoreCase)
        {
            "62e90394-69f5-4237-9190-012177145e10", // Global Administrator
            "e8611ab8-c189-46e8-94e1-60213ab1f814", // Privileged Role Administrator
            "194ae4cb-b126-40b2-bd5b-6091b380977d", // Security Administrator
            "fe930be7-5e62-47db-91af-98c3a49a38b1", // User Administrator
            "729827e3-9c14-49f7-bb1b-9608f156bbb8", // Helpdesk Administrator
            "f28a1f50-f6e7-4571-818b-6a12f2af6b6c", // SharePoint Administrator
            "29232cdf-9323-42fd-ade2-1d097af3e4de", // Exchange Administrator
            "69091246-20e8-4a56-aa4d-066075b2a7a8", // Teams Administrator
            "158c047a-c907-4556-b7ef-446551a6b5f7", // Cloud Application Administrator
            "9b895d92-2cd3-44c7-9d02-a6ac2d5ea5c3", // Application Administrator
            "b0f54661-2d74-4c50-afa3-1ec803f12efe", // Billing Administrator
            "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9", // Conditional Access Administrator
            "966707d0-3269-4727-9be2-8c3a10f19b9d", // Password Administrator
            "e3973bdf-4987-49ae-837a-ba8e231c7286", // Azure DevOps Administrator
            "7be44c8a-adaf-4e2a-84d6-ab2649e08a13", // Privileged Authentication Administrator
        };

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var assignments = data.Get("RoleAssignmentScheduleInstances");
            if (!Any(assignments))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var permanent = new List<JsonElement>();
            foreach (var a in Items(assignments))
            {
                var roleDefId = Str(a, "roleDefinitionId");
                if (roleDefId == null || !PrivilegedRoleTemplateIds.Contains(roleDefId)) continue;
                if (StrEq(a, "assignmentType", "Assigned") && PropIn(a, "memberType", "Direct", "Group"))
                    permanent.Add(a);
            }

            if (permanent.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    "No permanent (non-PIM) assignments found for privileged Microsoft Entra roles.");

            var lines = new List<string>
            {
                $"{permanent.Count} permanent assignment(s) found for privileged Microsoft Entra roles. These should be managed via PIM eligibility instead.",
                "",
                "| Principal | Role Definition ID | Assignment Type | Member Type |",
                "| :-------- | :----------------- | :-------------- | :---------- |"
            };

            for (int i = 0; i < permanent.Count && i < 25; i++)
            {
                var a = permanent[i];
                lines.Add($"| {Text(a, "principalId")} | {Text(a, "roleDefinitionId")} | {Text(a, "assignmentType")} | {Text(a, "memberType")} |");
            }

            if (permanent.Count > 25)
            {
                lines.Add("");
                lines.Add($"...and {permanent.Count - 25} more.");
            }

            lines.Add("");
            lines.Add("**Remediation:** Move standing privileged role assignments into PIM as eligible assignments so users must activate the role just-in-time with MFA and approval.");

            return new CippTestResult(TestStatus.Failed, string.Join("\n", lines));
        }
    }
}
