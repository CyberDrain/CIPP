using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (Restrict Admin Privileges) — no privileged account inactive for more than 45 days
    /// (ISM-1648). Port of Invoke-CippTestE8_Admin_05. Enabled privileged users whose last sign-in
    /// is older than 45 days are flagged; users with no recorded sign-in are treated as compliant.
    /// </summary>
    public sealed class E8_Admin_05 : ICippTest
    {
        public string Id => "E8_Admin_05";

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
                .Where(u => privUserIds.Contains(CippTestHelpers.Str(u, "id") ?? "") && CippTestHelpers.IsTrue(u, "accountEnabled"))
                .ToList();

            if (privUsers.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed, "No enabled privileged users found.");
            }

            var threshold = DateTime.UtcNow.AddDays(-45);
            var stale = new List<(string Upn, string LastSignIn)>();
            foreach (var u in privUsers)
            {
                var last = CippTestHelpers.PathStr(u, "signInActivity", "lastSignInDateTime");
                if (string.IsNullOrEmpty(last)) continue;
                if (!CippTestHelpers.TryParseUtc(last, out var lastDt)) continue;
                if (lastDt < threshold)
                {
                    stale.Add((CippTestHelpers.Str(u, "userPrincipalName") ?? "",
                        lastDt.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)));
                }
            }

            if (stale.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {privUsers.Count} enabled privileged user(s) signed in within the last 45 days (or have no recorded sign-in).");
            }

            var sb = new StringBuilder();
            sb.Append($"{stale.Count} of {privUsers.Count} enabled privileged user(s) have not signed in for more than 45 days:\n\n");
            var rows = stale.OrderBy(s => s.LastSignIn, StringComparer.Ordinal).Take(50)
                .Select(s => (IReadOnlyList<string>)new[] { s.Upn, s.LastSignIn });
            sb.Append(Markdown.Table(new[] { "UPN", "Last sign-in" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
