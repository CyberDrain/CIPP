using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// All privileged role assignments are activated just in time and not permanently active.
    /// Port of Invoke-CippTestZTNA21815. Fails if any privileged role has an active PIM assignment
    /// (assignmentType 'Assigned') with no endDateTime for a user found in Users.
    /// </summary>
    public sealed class ZTNA21815 : ICippTest
    {
        public string Id => "ZTNA21815";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var privilegedRoles = PrivilegedRoles(data);
            var activeInstances = data.Get("RoleAssignmentScheduleInstances");
            var users = data.Get("Users");
            var usersById = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            foreach (var u in Items(users)) { var id = Str(u, "id"); if (id != null && !usersById.ContainsKey(id)) usersById[id] = u; }

            var permanent = new List<(string Display, string Upn, string Id, string Role)>();
            foreach (var role in privilegedRoles)
            {
                var tid = RoleTemplateId(role);
                if (tid == null) continue;
                var roleName = Str(role, "displayName") ?? "";
                foreach (var a in Items(activeInstances))
                {
                    if (!StrEq(a, "roleDefinitionId", tid) || !StrEq(a, "assignmentType", "Assigned")) continue;
                    var end = Prop(a, "endDateTime");
                    if (!(end.ValueKind == JsonValueKind.Null || end.ValueKind == JsonValueKind.Undefined)) continue;
                    var pid = Str(a, "principalId");
                    if (pid == null || !usersById.TryGetValue(pid, out var user)) continue;
                    permanent.Add((Str(user, "displayName") ?? "", Str(user, "userPrincipalName") ?? "", pid, roleName));
                }
            }

            if (permanent.Count == 0)
                return new CippTestResult(TestStatus.Passed, "No privileged users have permanent role assignments.");

            var sb = new StringBuilder("Privileged users with permanent role assignments were found.\n\n");
            sb.Append("## Privileged users with permanent role assignments\n\n");
            sb.Append("| User | UPN | Role Name | Assignment Type |\n");
            sb.Append("| :--- | :-- | :-------- | :-------------- |\n");
            foreach (var e in permanent)
            {
                var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/{e.Id}/hidePreviewBanner~/true";
                sb.Append($"| [{e.Display}]({link}) | {e.Upn} | {e.Role} | Permanent |\n");
            }

            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
