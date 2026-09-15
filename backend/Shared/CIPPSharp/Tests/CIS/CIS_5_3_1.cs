using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.3.1) — Privileged role assignments SHALL be activated and not assigned.
    /// Port of Invoke-CippTestCIS_5_3_1. Standing (permanent) active assignments in privileged roles
    /// must move to PIM eligibility; up to two permanent Global Administrator break-glass accounts are
    /// tolerated. Joins RoleAssignmentScheduleInstances to Roles for display names.
    /// </summary>
    public sealed class CIS_5_3_1 : ICippTest
    {
        public string Id => "CIS_5_3_1";

        private const string GaTemplateId = "62e90394-69f5-4237-9190-012177145e10";

        private static readonly HashSet<string> PrivilegedRoleNames = new(StringComparer.OrdinalIgnoreCase)
        {
            "Global Administrator", "Privileged Role Administrator", "Privileged Authentication Administrator",
            "Security Administrator", "Exchange Administrator", "SharePoint Administrator", "User Administrator",
            "Conditional Access Administrator", "Application Administrator", "Cloud Application Administrator",
            "Hybrid Identity Administrator", "Intune Administrator", "Authentication Administrator",
            "Helpdesk Administrator", "Password Administrator", "Domain Name Administrator",
        };

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var active = data.Get("RoleAssignmentScheduleInstances");
            var roles = data.Get("Roles");

            if (!Any(active))
                return new CippTestResult(TestStatus.Skipped,
                    "RoleAssignmentScheduleInstances cache not found. Please refresh the cache for this tenant.");

            // roleTemplateId → displayName (case-insensitive keys, matching a PS hashtable).
            var roleNames = new Dictionary<string, string?>(StringComparer.OrdinalIgnoreCase);
            foreach (var r in Items(roles))
            {
                var tid = Str(r, "roleTemplateId");
                if (!string.IsNullOrEmpty(tid)) roleNames[tid!] = Str(r, "displayName");
            }

            // Standing (permanent) active assignments = assignmentType 'Assigned' with no end date.
            var gaPermanent = 0;
            var otherPrivPermanent = new List<string?>();
            foreach (var a in active.EnumerateArray())
            {
                if (!StrEq(a, "assignmentType", "Assigned") || !EndDateNullOrEmpty(a)) continue;
                var rdid = Str(a, "roleDefinitionId");
                if (rdid != null && string.Equals(rdid, GaTemplateId, StringComparison.OrdinalIgnoreCase))
                {
                    gaPermanent++;
                }
                else
                {
                    string? name = rdid != null && roleNames.TryGetValue(rdid, out var n) ? n : null;
                    if (name != null && PrivilegedRoleNames.Contains(name)) otherPrivPermanent.Add(name);
                }
            }

            var violations = new List<string>();
            if (gaPermanent > 2)
                violations.Add($"{gaPermanent} permanent Global Administrator assignments (only up to 2 break-glass accounts may be permanently assigned).");
            if (otherPrivPermanent.Count > 0)
            {
                var unique = new List<string>(new HashSet<string>(
                    otherPrivPermanent.ConvertAll(x => x!), StringComparer.OrdinalIgnoreCase));
                unique.Sort(StringComparer.OrdinalIgnoreCase);
                var names = string.Join(", ", unique);
                violations.Add($"{otherPrivPermanent.Count} permanent assignment(s) in privileged roles that should use PIM activation: {names}.");
            }

            if (violations.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"No non-compliant standing privileged assignments found (Global Administrator permanent assignments: {gaPermanent}/2 break-glass). Confirm any remaining privileged roles use eligible (PIM) assignments.");
            }

            var sb = new StringBuilder();
            sb.Append("Standing privileged role assignments should be moved to PIM eligibility (activated, not permanently assigned):\n\n- ");
            sb.Append(string.Join("\n- ", violations));
            return new CippTestResult(TestStatus.Failed, sb.ToString());
        }
    }
}
