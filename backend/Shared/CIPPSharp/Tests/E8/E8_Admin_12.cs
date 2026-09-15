using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Restrict Admin Privileges) — Global Administrator count is between 2 and 4. Port of
    /// Invoke-CippTestE8_Admin_12. Counts user-type GAs only (role members + active PIM assignments).
    /// Reads Roles + RoleAssignmentScheduleInstances.
    /// </summary>
    public sealed class E8_Admin_12 : ICippTest
    {
        public string Id => "E8_Admin_12";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var roles = data.Get("Roles");
            if (!CippTestHelpers.Any(roles))
            {
                return new CippTestResult(TestStatus.Skipped, "Required cache (Roles) not found.");
            }

            var gaRole = CippTestHelpers.Items(roles)
                .FirstOrDefault(r => CippTestHelpers.StrEq(r, "displayName", "Global Administrator"));
            if (gaRole.ValueKind != JsonValueKind.Object)
            {
                return new CippTestResult(TestStatus.Skipped, "Global Administrator role not present in cache.");
            }

            var gaTemplateId = CippTestHelpers.RoleTemplateId(gaRole);
            var gaUserIds = new HashSet<string>(StringComparer.Ordinal);
            foreach (var m in CippTestHelpers.Arr(gaRole, "members"))
            {
                var id = CippTestHelpers.Str(m, "id");
                if (!string.IsNullOrEmpty(id) && CippTestHelpers.StrEq(m, "@odata.type", "#microsoft.graph.user"))
                    gaUserIds.Add(id!);
            }
            if (!string.IsNullOrEmpty(gaTemplateId))
            {
                foreach (var (roleDefId, principalId) in CippTestHelpers.ActiveRoleAssignments(data))
                {
                    if (string.Equals(roleDefId, gaTemplateId, StringComparison.OrdinalIgnoreCase))
                        gaUserIds.Add(principalId);
                }
            }

            var gaCount = gaUserIds.Count;
            if (gaCount >= 2 && gaCount <= 4)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"{gaCount} Global Administrator(s) — within recommended range of 2-4.");
            }
            if (gaCount < 2)
            {
                return new CippTestResult(TestStatus.Failed,
                    $"Only {gaCount} Global Administrator(s). At least 2 are required so a single account loss does not lock the tenant.");
            }
            return new CippTestResult(TestStatus.Failed,
                $"{gaCount} Global Administrators — exceeds the recommended maximum of 4. Reduce by delegating finer-grained roles.");
        }
    }
}
