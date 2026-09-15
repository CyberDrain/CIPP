using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Restrict Admin Privileges) — privileged accounts have no productivity licenses
    /// (ISM-1175). Port of Invoke-CippTestE8_Admin_02. A privileged user with any assigned license
    /// is non-compliant.
    /// </summary>
    public sealed class E8_Admin_02 : ICippTest
    {
        public string Id => "E8_Admin_02";

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

            var licensed = privUsers
                .Where(u => CippTestHelpers.TryProp(u, "assignedLicenses", out var l)
                    && l.ValueKind == JsonValueKind.Array && l.GetArrayLength() > 0)
                .ToList();

            if (licensed.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {privUsers.Count} privileged user(s) have no licenses assigned.");
            }

            var sb = new StringBuilder();
            sb.Append($"{licensed.Count} of {privUsers.Count} privileged user(s) have productivity licenses assigned. ACSC ISM-1175 requires admins not to use mail/Teams/internet on the privileged account.\n\n");
            var rows = licensed.Take(50).Select(u =>
            {
                CippTestHelpers.TryProp(u, "assignedLicenses", out var l);
                var count = l.ValueKind == JsonValueKind.Array ? l.GetArrayLength() : 0;
                return (IReadOnlyList<string>)new[] { CippTestHelpers.Str(u, "userPrincipalName") ?? "", count.ToString() };
            });
            sb.Append(Markdown.Table(new[] { "UPN", "License count" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
