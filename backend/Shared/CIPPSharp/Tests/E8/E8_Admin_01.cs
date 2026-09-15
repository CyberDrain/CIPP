using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Restrict Admin Privileges) — privileged accounts are dedicated cloud-only accounts
    /// (ISM-0445). Port of Invoke-CippTestE8_Admin_01. Joins privileged Roles + PIM assignments +
    /// Users; a privileged user synced from on-premises AD (onPremisesSyncEnabled) is non-compliant.
    /// </summary>
    public sealed class E8_Admin_01 : ICippTest
    {
        public string Id => "E8_Admin_01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var privRoles = CippTestHelpers.PrivilegedRoles(data);
            var users = data.Get("Users");
            if (privRoles.Count == 0 || !CippTestHelpers.Any(users))
            {
                return new CippTestResult(TestStatus.Skipped, "Required cache (Roles or Users) not found.");
            }

            var privUserIds = CippTestHelpers.PrivilegedUserIds(privRoles, data, userMembersOnly: false);
            var privUsers = CippTestHelpers.Items(users)
                .Where(u => privUserIds.Contains(CippTestHelpers.Str(u, "id") ?? ""))
                .ToList();

            if (privUsers.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed, "No privileged users found.");
            }

            var nonCompliant = privUsers.Where(u => CippTestHelpers.IsTrue(u, "onPremisesSyncEnabled")).ToList();
            if (nonCompliant.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {privUsers.Count} privileged user(s) are cloud-only.");
            }

            var sb = new StringBuilder();
            sb.Append($"{nonCompliant.Count} of {privUsers.Count} privileged user(s) are synced from on-premises Active Directory:\n\n");
            var rows = nonCompliant.Take(50)
                .Select(u => (IReadOnlyList<string>)new[] { CippTestHelpers.Str(u, "userPrincipalName") ?? "" });
            sb.Append(Markdown.Table(new[] { "UPN" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
