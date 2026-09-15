using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (1.1.1) — Administrative accounts SHALL be cloud-only.
    /// Port of Invoke-CippTestCIS_1_1_1. Joins privileged roles + PIM assignments + Users.
    /// </summary>
    public sealed class CIS_1_1_1 : ICippTest
    {
        public string Id => "CIS_1_1_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var privRoles = GetPrivilegedRoles(data);
            var users = data.Get("Users");

            // PS: $Roles (privileged-filtered) is $null when no Roles cache OR no privileged roles.
            if (privRoles.Count == 0 || !Any(users))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (Roles or Users) not found. Please refresh the cache for this tenant.");
            }

            var privUserIds = CollectPrivilegedUserIds(data);
            var privilegedUsers = UsersByIds(data, privUserIds);

            if (privilegedUsers.Count == 0)
                return new CippTestResult(TestStatus.Passed, "No privileged users found.");

            var nonCompliant = new List<JsonElement>();
            foreach (var u in privilegedUsers)
            {
                var upn = Str(u, "userPrincipalName");
                bool synced = IsTrue(u, "onPremisesSyncEnabled");
                bool notOnMicrosoft = NotLikeCI(upn, "*onmicrosoft.com");
                bool licensed = ArrayCount(u, "assignedLicenses") > 0;
                if (synced || notOnMicrosoft || licensed) nonCompliant.Add(u);
            }

            if (nonCompliant.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"All {privilegedUsers.Count} privileged users are cloud-only and unlicensed.");
            }

            var sb = new StringBuilder();
            sb.Append($"{nonCompliant.Count} of {privilegedUsers.Count} privileged user(s) are not cloud-only or are licensed:\n\n");
            var rows = new List<IReadOnlyList<string>>();
            int shown = 0;
            foreach (var u in nonCompliant)
            {
                if (shown++ >= 25) break;
                rows.Add(new[]
                {
                    Str(u, "userPrincipalName") ?? "",
                    BoolStr(IsTrue(u, "onPremisesSyncEnabled")),
                    BoolStr(ArrayCount(u, "assignedLicenses") > 0),
                });
            }
            sb.Append(Markdown.Table(new[] { "UPN", "Synced", "Licensed" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
