using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// No nested groups in PIM for groups.
    /// Port of Invoke-CippTestZTNA21882. Skipped on no Groups data. Role-assignable groups whose
    /// members include entries without a userPrincipalName (implying a nested group) are flagged.
    /// Passed when no role-assignable groups exist or none contain nested members.
    /// </summary>
    public sealed class ZTNA21882 : ICippTest
    {
        public string Id => "ZTNA21882";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var groups = data.Get("Groups");
            if (!Any(groups))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            var roleAssignable = new List<JsonElement>();
            foreach (var g in Items(groups)) if (IsTrue(g, "isAssignableToRole")) roleAssignable.Add(g);

            if (roleAssignable.Count == 0)
                return new CippTestResult(TestStatus.Passed, "No role-assignable groups found in the tenant.");

            // (group, nestedCount, sample)
            var nested = new List<(JsonElement Group, int Count, string Sample)>();
            foreach (var g in roleAssignable)
            {
                var groupMembers = new List<JsonElement>();
                foreach (var m in Arr(g, "members"))
                    if (string.IsNullOrEmpty(Str(m, "userPrincipalName"))) groupMembers.Add(m);

                if (groupMembers.Count > 0)
                {
                    var sampleNames = new List<string>();
                    for (int i = 0; i < groupMembers.Count && i < 3; i++)
                        sampleNames.Add(Text(groupMembers[i], "displayName"));
                    nested.Add((g, groupMembers.Count, string.Join(", ", sampleNames)));
                }
            }

            if (nested.Count == 0)
                return new CippTestResult(TestStatus.Passed,
                    $"All {roleAssignable.Count} role-assignable group(s) contain only direct user members — no nested groups detected.");

            var lines = new List<string>
            {
                $"{nested.Count} of {roleAssignable.Count} role-assignable group(s) contain nested group members.",
                "",
                "| Group | Nested Members | Sample |",
                "| :---- | :------------- | :----- |"
            };

            for (int i = 0; i < nested.Count && i < 25; i++)
                lines.Add($"| {Text(nested[i].Group, "displayName")} | {nested[i].Count} | {nested[i].Sample} |");

            if (nested.Count > 25)
            {
                lines.Add("");
                lines.Add($"...and {nested.Count - 25} more.");
            }

            lines.Add("");
            lines.Add("**Remediation:** Replace nested-group memberships in role-assignable / PIM-managed groups with direct user assignments. Nesting bypasses the PIM activation flow for users in the nested group.");

            return new CippTestResult(TestStatus.Failed, string.Join("\n", lines));
        }
    }
}
