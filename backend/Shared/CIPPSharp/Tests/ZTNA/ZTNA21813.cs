using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// High Global Administrator to privileged user ratio.
    /// Port of Invoke-CippTestZTNA21813. Counts distinct GA-role users vs distinct other-privileged
    /// users across active + eligible assignments; Passed when the GA share is under 30% (or there are
    /// no privileged assignments). NOTE: the PS 'Investigate' CustomStatus for the 30-50% band is
    /// computed but never emitted (the Add-CippTestResult uses Passed/Failed), so this reproduces
    /// Failed for that band.
    /// </summary>
    public sealed class ZTNA21813 : ICippTest
    {
        private const string GlobalAdminRoleId = "62e90394-69f5-4237-9190-012177145e10";

        public string Id => "ZTNA21813";

        private sealed class RoleEntry
        {
            public JsonElement User;
            public string DisplayName = "";
            public List<string> Roles = new();
            public bool IsGA;
        }

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var privilegedRoles = PrivilegedRoles(data);
            var activeInstances = data.Get("RoleAssignmentScheduleInstances");
            var eligibleSchedules = data.Get("RoleEligibilitySchedules");
            var users = data.Get("Users");

            var usersById = new Dictionary<string, JsonElement>(StringComparer.Ordinal);
            foreach (var u in Items(users)) { var id = Str(u, "id"); if (id != null && !usersById.ContainsKey(id)) usersById[id] = u; }

            var allGa = new HashSet<string>(StringComparer.Ordinal);
            var allPriv = new HashSet<string>(StringComparer.Ordinal);
            var userRoleMap = new Dictionary<string, RoleEntry>(StringComparer.Ordinal);

            foreach (var role in privilegedRoles)
            {
                var tid = RoleTemplateId(role);
                if (tid == null) continue;
                var roleName = Str(role, "displayName") ?? "";
                bool isGaRole = string.Equals(tid, GlobalAdminRoleId, StringComparison.OrdinalIgnoreCase);

                var assignments = new List<JsonElement>();
                foreach (var a in Items(activeInstances))
                    if (StrEq(a, "roleDefinitionId", tid) && StrEq(a, "assignmentType", "Assigned")) assignments.Add(a);
                foreach (var e in Items(eligibleSchedules))
                    if (StrEq(e, "roleDefinitionId", tid)) assignments.Add(e);

                foreach (var a in assignments)
                {
                    var pid = Str(a, "principalId");
                    if (pid == null || !usersById.TryGetValue(pid, out var user)) continue;

                    if (isGaRole) allGa.Add(pid); else allPriv.Add(pid);

                    if (!userRoleMap.TryGetValue(pid, out var entry))
                    {
                        entry = new RoleEntry { User = user, DisplayName = Str(user, "displayName") ?? "" };
                        userRoleMap[pid] = entry;
                    }
                    if (!entry.Roles.Contains(roleName)) entry.Roles.Add(roleName);
                    if (isGaRole) entry.IsGA = true;
                }
            }

            int gaCount = allGa.Count;
            int privCount = allPriv.Count;
            int total = gaCount + privCount;

            double gaPct = total > 0 ? Math.Round((double)gaCount / total * 100, 2) : 0;
            double otherPct = total > 0 ? Math.Round((double)privCount / total * 100, 2) : 0;

            bool healthy = gaPct < 30;
            bool moderate = gaPct >= 30 && gaPct < 50;

            string statusIndicator = healthy ? "✅ Passed" : (moderate ? "⚠️ Investigate" : "❌ Failed");

            var md = new StringBuilder("\n## Privileged role assignment summary\n\n");
            md.Append($"**Global administrator role count:** {gaCount} ({gaPct.ToString(CultureInfo.InvariantCulture)}%) - {statusIndicator}\n\n");
            md.Append($"**Other privileged role count:** {privCount} ({otherPct.ToString(CultureInfo.InvariantCulture)}%)\n\n");
            md.Append("## User privileged role assignments\n\n");
            md.Append("| User | Global administrator | Other Privileged Role(s) |\n");
            md.Append("| :--- | :------------------- | :------ |\n");

            var sorted = userRoleMap.Values
                .OrderBy(e => e.IsGA ? 0 : 1)
                .ThenBy(e => e.DisplayName, StringComparer.Ordinal);
            foreach (var e in sorted)
            {
                string isGa = e.IsGA ? "Yes" : "No";
                var other = e.Roles.Where(r => r != "Global Administrator").OrderBy(r => r, StringComparer.Ordinal).ToList();
                string rolesList = other.Count > 0 ? string.Join(", ", other) : "-";
                var uid = Str(e.User, "id");
                var link = $"https://entra.microsoft.com/#view/Microsoft_AAD_UsersAndTenants/UserProfileMenuBlade/~/AdministrativeRole/userId/{uid}/hidePreviewBanner~/true";
                md.Append($"| [{e.DisplayName}]({link}) | {isGa} | {rolesList} |\n");
            }
            if (userRoleMap.Count == 0)
                md.Append("| No privileged users found | - | - |\n");

            bool passed;
            string header;
            if (total == 0) { passed = true; header = "No privileged role assignments found in the tenant."; }
            else if (healthy) { passed = true; header = "Less than 30% of privileged role assignments in the tenant are Global Administrator."; }
            else if (moderate) { passed = false; header = "Between 30-50% of privileged role assignments in the tenant are Global Administrator."; }
            else { passed = false; header = "More than 50% of privileged role assignments in the tenant are Global Administrator."; }

            return new CippTestResult(passed ? TestStatus.Passed : TestStatus.Failed, header + md.ToString());
        }
    }
}
