using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Privileged accounts are cloud native identities.
    /// Port of Invoke-CippTestZTNA21814. For every privileged-role user member joined to Users,
    /// fails if any is synced from on-premises (onPremisesSyncEnabled == true).
    /// </summary>
    public sealed class ZTNA21814 : ICippTest
    {
        public string Id => "ZTNA21814";

        private sealed class Row
        {
            public string RoleName = "";
            public string UserId = "";
            public string UserDisplayName = "";
            public bool Synced;
        }

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var privilegedRoles = PrivilegedRoles(data);
            var users = data.Get("Users");
            var usersById = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            foreach (var u in Items(users)) { var id = Str(u, "id"); if (id != null && !usersById.ContainsKey(id)) usersById[id] = u; }

            var roleData = new List<Row>();
            foreach (var role in privilegedRoles)
            {
                var tid = RoleTemplateId(role);
                if (tid == null) continue;
                var roleName = Str(role, "displayName") ?? "";
                foreach (var member in CippTestHelpers.RoleMembers(data, tid))
                {
                    if (!member.IsUser) continue;
                    if (member.Id == null || !usersById.TryGetValue(member.Id, out var user)) continue;
                    roleData.Add(new Row
                    {
                        RoleName = roleName,
                        UserId = Str(user, "id") ?? "",
                        UserDisplayName = Str(user, "displayName") ?? "",
                        Synced = IsTrue(user, "onPremisesSyncEnabled")
                    });
                }
            }

            int syncedCount = roleData.Count(r => r.Synced);
            bool passed = syncedCount == 0;

            var sb = new StringBuilder(passed
                ? "Validated that standing or eligible privileged accounts are cloud only accounts.\n\n"
                : $"This tenant has {syncedCount} privileged users that are synced from on-premise.\n\n");

            if (roleData.Count > 0)
            {
                sb.Append("## Privileged Roles\n\n");
                sb.Append("| Role Name | User | Source | Status |\n");
                sb.Append("| :--- | :--- | :--- | :---: |\n");
                foreach (var r in roleData.OrderBy(x => x.RoleName, StringComparer.Ordinal).ThenBy(x => x.UserDisplayName, StringComparer.Ordinal))
                {
                    string type = r.Synced ? "Synced from on-premise" : "Cloud native identity";
                    string status = r.Synced ? "❌" : "✅";
                    var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/{r.UserId}";
                    sb.Append($"| {r.RoleName} | [{r.UserDisplayName}]({link}) | {type} | {status} |\n");
                }
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }
    }
}
