using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// All Microsoft Entra privileged role assignments are managed with PIM.
    /// Port of Invoke-CippTestZTNA21816. Checks that non-GA privileged members are PIM-managed (have a
    /// non-permanent assignment) and that permanent Global Administrators are limited. NOTE: the PS
    /// 'Investigate' CustomStatus for &gt;2 permanent GAs is computed but never emitted (Passed/Failed
    /// only), so this reproduces Failed for that band.
    /// </summary>
    public sealed class ZTNA21816 : ICippTest
    {
        private const string GlobalAdminRoleId = "62e90394-69f5-4237-9190-012177145e10";

        public string Id => "ZTNA21816";

        private sealed class MemberInfo
        {
            public string DisplayName = "";
            public string Upn = "";
            public string Id = "";
            public string RoleName = "";
            public string AssignmentType = "";
            public string SyncDisplay = "N/A";
        }

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var privilegedRoles = PrivilegedRoles(data);
            var eligibleSchedules = data.Get("RoleEligibilitySchedules");
            var activeInstances = data.Get("RoleAssignmentScheduleInstances");
            var users = data.Get("Users");
            var groups = data.Get("Groups");

            var usersById = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            foreach (var u in Items(users)) { var id = Str(u, "id"); if (id != null) usersById[id] = u; }
            var groupsById = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            foreach (var g in Items(groups)) { var id = Str(g, "id"); if (id != null) groupsById[id] = g; }

            // principalId|roleDefinitionId -> first assignment.
            var assignmentByPrincipalRole = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            foreach (var a in Items(activeInstances))
            {
                var key = (Str(a, "principalId") ?? "") + "|" + (Str(a, "roleDefinitionId") ?? "");
                if (!assignmentByPrincipalRole.ContainsKey(key)) assignmentByPrincipalRole[key] = a;
            }

            // Eligible GA users (direct users + user members of eligible groups).
            int eligibleGaUsers = 0;
            foreach (var e in Items(eligibleSchedules))
            {
                if (!StrEq(e, "roleDefinitionId", GlobalAdminRoleId)) continue;
                var pid = Str(e, "principalId");
                if (pid != null && usersById.ContainsKey(pid)) { eligibleGaUsers++; continue; }
                if (pid != null && groupsById.TryGetValue(pid, out var group))
                {
                    var memberSet = GroupMemberSet(group);
                    if (memberSet.Count > 0)
                        foreach (var u in Items(users)) { var uid = Str(u, "id"); if (uid != null && memberSet.Contains(uid)) eligibleGaUsers++; }
                }
            }

            var nonPimUsers = new List<MemberInfo>();
            var nonPimGroups = new List<MemberInfo>();
            var permanentGaUsers = new List<MemberInfo>();
            int permanentGaGroups = 0;

            foreach (var role in privilegedRoles)
            {
                var tid = RoleTemplateId(role);
                if (tid == null) continue;
                if (string.Equals(tid, GlobalAdminRoleId, StringComparison.OrdinalIgnoreCase)) continue;
                var roleName = Str(role, "displayName") ?? "";

                foreach (var member in CippTestHelpers.RoleMembers(data, tid))
                {
                    var mid = member.Id ?? "";
                    bool hasAssignment = assignmentByPrincipalRole.TryGetValue(mid + "|" + tid, out var assignment);
                    if (FlagAsNonPim(hasAssignment, assignment))
                    {
                        var info = new MemberInfo
                        {
                            DisplayName = member.DisplayName ?? "",
                            Upn = member.UserPrincipalName ?? "",
                            Id = mid,
                            RoleName = roleName,
                            AssignmentType = hasAssignment ? (Str(assignment, "assignmentType") ?? "") : "Not in PIM"
                        };
                        if (member.IsUser) nonPimUsers.Add(info); else nonPimGroups.Add(info);
                    }
                }
            }

            foreach (var member in CippTestHelpers.RoleMembers(data, GlobalAdminRoleId))
            {
                var mid = member.Id ?? "";
                bool hasAssignment = assignmentByPrincipalRole.TryGetValue(mid + "|" + GlobalAdminRoleId, out var assignment);
                if (!FlagAsNonPim(hasAssignment, assignment)) continue;

                string assignmentType = hasAssignment ? (Str(assignment, "assignmentType") ?? "") : "Not in PIM";
                if (member.IsUser)
                {
                    var info = new MemberInfo
                    {
                        DisplayName = member.DisplayName ?? "",
                        Upn = member.UserPrincipalName ?? "",
                        Id = mid,
                        RoleName = "Global Administrator",
                        AssignmentType = assignmentType
                    };
                    if (usersById.TryGetValue(mid, out var ud))
                        info.SyncDisplay = SyncDisplay(Prop(ud, "onPremisesSyncEnabled"));
                    permanentGaUsers.Add(info);
                }
                else if (member.IsGroup)
                {
                    permanentGaGroups++;
                    if (groupsById.TryGetValue(mid, out var group))
                    {
                        var memberSet = GroupMemberSet(group);
                        if (memberSet.Count > 0)
                            foreach (var gm in Items(users))
                            {
                                var gid = Str(gm, "id");
                                if (gid == null || !memberSet.Contains(gid)) continue;
                                permanentGaUsers.Add(new MemberInfo
                                {
                                    DisplayName = Str(gm, "displayName") ?? "",
                                    Upn = Str(gm, "userPrincipalName") ?? "",
                                    Id = gid,
                                    RoleName = "Global Administrator (via group)",
                                    AssignmentType = "Via Group",
                                    SyncDisplay = SyncDisplay(Prop(gm, "onPremisesSyncEnabled"))
                                });
                            }
                    }
                }
            }

            bool hasPimUsage = eligibleGaUsers > 0;
            bool hasNonPim = (nonPimUsers.Count + nonPimGroups.Count) > 0;
            int permanentGaCount = permanentGaUsers.Count;

            bool passed;
            string header;
            if (!hasPimUsage) { passed = false; header = "No eligible Global Administrator assignments found. PIM usage cannot be confirmed."; }
            else if (hasNonPim) { passed = false; header = "Found Microsoft Entra privileged role assignments that are not managed with PIM."; }
            else if (permanentGaCount > 2) { passed = false; header = "Three or more accounts are permanently assigned the Global Administrator role. Review to determine whether these are emergency access accounts."; }
            else { passed = true; header = "All Microsoft Entra privileged role assignments are managed with PIM with the exception of up to two standing Global Administrator accounts."; }

            var sb = new StringBuilder(header);
            sb.Append("\n\n## Assessment summary\n\n");
            sb.Append("| Metric | Count |\n");
            sb.Append("| :----- | :---- |\n");
            sb.Append($"| Privileged roles found | {privilegedRoles.Count} |\n");
            sb.Append($"| Eligible Global Administrators | {eligibleGaUsers} |\n");
            sb.Append($"| Non-PIM privileged users | {nonPimUsers.Count} |\n");
            sb.Append($"| Non-PIM privileged groups | {nonPimGroups.Count} |\n");
            sb.Append($"| Permanent Global Administrator users | {permanentGaUsers.Count} |\n");

            if (nonPimUsers.Count > 0 || nonPimGroups.Count > 0)
            {
                sb.Append("\n## Non-PIM managed privileged role assignments\n\n");
                sb.Append("| Display name | User principal name | Role name | Assignment type |\n");
                sb.Append("| :----------- | :------------------ | :-------- | :-------------- |\n");
                foreach (var u in nonPimUsers)
                {
                    var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/{u.Id}/hidePreviewBanner~/true";
                    sb.Append($"| [{u.DisplayName}]({link}) | {u.Upn} | {u.RoleName} | {u.AssignmentType} |\n");
                }
                foreach (var g in nonPimGroups)
                {
                    var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_IAM/GroupDetailsMenuBlade/~/RolesAndAdministrators/groupId/{g.Id}/menuId/";
                    sb.Append($"| [{g.DisplayName}]({link}) | N/A (Group) | {g.RoleName} | {g.AssignmentType} |\n");
                }
            }

            if (permanentGaUsers.Count > 0)
            {
                sb.Append("\n## Permanent Global Administrator assignments\n\n");
                sb.Append("| Display name | User principal name | Assignment type | On-Premises synced |\n");
                sb.Append("| :----------- | :------------------ | :-------------- | :----------------- |\n");
                foreach (var u in permanentGaUsers)
                {
                    var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/{u.Id}/hidePreviewBanner~/true";
                    sb.Append($"| [{u.DisplayName}]({link}) | {u.Upn} | {u.AssignmentType} | {u.SyncDisplay} |\n");
                }
            }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, sb.ToString());
        }

        // -not $Assignment -or ($Assignment.assignmentType -eq 'Assigned' -and $null -eq $Assignment.endDateTime)
        private static bool FlagAsNonPim(bool hasAssignment, JsonElement assignment)
        {
            if (!hasAssignment) return true;
            if (!StrEq(assignment, "assignmentType", "Assigned")) return false;
            var end = Prop(assignment, "endDateTime");
            return end.ValueKind == JsonValueKind.Null || end.ValueKind == JsonValueKind.Undefined;
        }

        private static string SyncDisplay(JsonElement onPrem)
        {
            if (onPrem.ValueKind == JsonValueKind.Null || onPrem.ValueKind == JsonValueKind.Undefined) return "N/A";
            return Cell(onPrem);
        }

        private static HashSet<string> GroupMemberSet(JsonElement group)
        {
            var set = new HashSet<string>(StringComparer.Ordinal);
            foreach (var m in Arr(group, "members"))
            {
                var s = AsString(m);
                if (s != null) set.Add(s);
            }
            return set;
        }
    }
}
