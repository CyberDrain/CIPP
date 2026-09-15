using System;
using System.Collections.Generic;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// Guests are not assigned high privileged directory roles.
    /// Port of Invoke-CippTestZTNA22128. Skipped when Roles or Guests is missing. Failed when any guest
    /// (matched by object id) is a member of a privileged directory role.
    /// </summary>
    public sealed class ZTNA22128 : ICippTest
    {
        public string Id => "ZTNA22128";

        private static readonly HashSet<string> PrivilegedRoleTemplateIds = new(StringComparer.OrdinalIgnoreCase)
        {
            "62e90394-69f5-4237-9190-012177145e10",
            "194ae4cb-b126-40b2-bd5b-6091b380977d",
            "f28a1f50-f6e7-4571-818b-6a12f2af6b6c",
            "29232cdf-9323-42fd-ade2-1d097af3e4de",
            "b1be1c3e-b65d-4f19-8427-f6fa0d97feb9",
            "729827e3-9c14-49f7-bb1b-9608f156bbb8",
            "b0f54661-2d74-4c50-afa3-1ec803f12efe",
            "fe930be7-5e62-47db-91af-98c3a49a38b1",
        };

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var roles = data.Get("Roles");
            var guests = data.Get("Guests");

            if (!Any(roles) || !Any(guests))
                return new CippTestResult(TestStatus.Skipped,
                    "No data found in database. This may be due to missing required licenses or data collection not yet completed.");

            int guestCount = guests.GetArrayLength();

            var guestIds = new HashSet<string>(StringComparer.Ordinal);
            foreach (var g in Items(guests))
            {
                var id = Str(g, "id");
                if (id != null) guestIds.Add(id);
            }

            // Grouped by role name, first-occurrence order.
            var order = new List<string>();
            var byRole = new Dictionary<string, List<(string Display, string Upn)>>(StringComparer.Ordinal);
            int totalFound = 0;

            foreach (var role in Items(roles))
            {
                var templateId = Str(role, "roleTemplateId");
                if (templateId == null || !PrivilegedRoleTemplateIds.Contains(templateId)) continue;
                var roleName = Text(role, "displayName");
                foreach (var member in Arr(role, "members"))
                {
                    var mid = Str(member, "id");
                    if (mid == null || !guestIds.Contains(mid)) continue;
                    if (!byRole.TryGetValue(roleName, out var list))
                    {
                        list = new List<(string, string)>();
                        byRole[roleName] = list;
                        order.Add(roleName);
                    }
                    list.Add((Text(member, "displayName"), Text(member, "userPrincipalName")));
                    totalFound++;
                }
            }

            if (totalFound == 0)
                return new CippTestResult(TestStatus.Passed,
                    "Guests with privileged roles were not found. All users with privileged roles are members of the tenant");

            var lines = new List<string>
            {
                $"Found {totalFound} guest user(s) with privileged role assignments.",
                "",
                $"**Total guests in tenant:** {guestCount}",
                $"**Guests with privileged roles:** {totalFound}",
                "",
                "**Guest users in privileged roles:**"
            };

            foreach (var roleName in order)
            {
                var list = byRole[roleName];
                lines.Add("");
                lines.Add($"**{roleName}** ({list.Count} guest(s)):");
                foreach (var g in list)
                    lines.Add($"- {g.Display} ({g.Upn})");
            }

            lines.Add("");
            lines.Add("**Security concern:** Guest users should not have privileged directory roles. Consider using separate admin accounts for external administrators or removing privileged access.");

            return new CippTestResult(TestStatus.Failed, string.Join("\n", lines));
        }
    }
}
