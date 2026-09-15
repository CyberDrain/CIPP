using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML3 (Restrict Admin Privileges) — Just-in-Time activation (PIM eligibility) is used for
    /// highly privileged roles. Port of Invoke-CippTestE8_Admin_08. Flags highly-privileged roles
    /// with permanent (non-PIM) active assignments. Reads Roles + RoleAssignmentScheduleInstances.
    /// </summary>
    public sealed class E8_Admin_08 : ICippTest
    {
        private static readonly HashSet<string> HighlyPriv = new(StringComparer.OrdinalIgnoreCase)
        {
            "Global Administrator", "Privileged Role Administrator", "Privileged Authentication Administrator",
            "Conditional Access Administrator", "Intune Administrator", "Security Administrator"
        };

        public string Id => "E8_Admin_08";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var roles = data.Get("Roles");
            if (!CippTestHelpers.Any(roles))
            {
                return new CippTestResult(TestStatus.Skipped, "Required cache (Roles) not found.");
            }
            if (!CippTestHelpers.Any(data.Get("RoleAssignmentScheduleInstances")))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "RoleAssignmentScheduleInstances (PIM active assignments) cache not found — cannot verify whether highly-privileged roles use Just-in-Time activation.");
            }

            var targetRoles = CippTestHelpers.Items(roles)
                .Where(r => HighlyPriv.Contains(CippTestHelpers.Str(r, "displayName") ?? ""))
                .ToList();
            if (targetRoles.Count == 0)
            {
                return new CippTestResult(TestStatus.Skipped, "No highly-privileged roles found in cache.");
            }

            // template id -> display name (insertion order preserved; CI keys as PS @{} is CI)
            var targetRoleTemplates = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            var order = new List<string>();
            foreach (var r in targetRoles)
            {
                var tid = CippTestHelpers.RoleTemplateId(r);
                if (string.IsNullOrEmpty(tid)) continue;
                if (!targetRoleTemplates.ContainsKey(tid!)) order.Add(tid!);
                targetRoleTemplates[tid!] = CippTestHelpers.Str(r, "displayName") ?? "";
            }

            var permanentByRole = new Dictionary<string, HashSet<string>>(StringComparer.OrdinalIgnoreCase);
            foreach (var (roleDefId, principalId) in CippTestHelpers.ActiveRoleAssignments(data))
            {
                if (!targetRoleTemplates.ContainsKey(roleDefId)) continue;
                if (!permanentByRole.TryGetValue(roleDefId, out var set))
                {
                    set = new HashSet<string>(StringComparer.Ordinal);
                    permanentByRole[roleDefId] = set;
                }
                set.Add(principalId);
            }

            var rolesWithPermanent = new List<(string Role, int Permanent)>();
            foreach (var tid in order)
            {
                var count = permanentByRole.TryGetValue(tid, out var s) ? s.Count : 0;
                if (count > 0) rolesWithPermanent.Add((targetRoleTemplates[tid], count));
            }

            if (rolesWithPermanent.Count == 0)
            {
                var names = string.Join(", ", targetRoles.Select(r => CippTestHelpers.Str(r, "displayName") ?? ""));
                return new CippTestResult(TestStatus.Passed,
                    $"No permanent role assignments found for highly-privileged roles ({names}). All access appears to be PIM-eligible.");
            }

            var sb = new StringBuilder();
            sb.Append("Permanent (non-PIM) assignments to highly-privileged roles:\n\n");
            var rows = rolesWithPermanent
                .Select(r => (IReadOnlyList<string>)new[] { r.Role, r.Permanent.ToString(CultureInfo.InvariantCulture) });
            sb.Append(Markdown.Table(new[] { "Role", "Permanent assignees" }, rows));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
