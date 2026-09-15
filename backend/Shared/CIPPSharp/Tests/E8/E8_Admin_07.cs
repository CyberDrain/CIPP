using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (Restrict Admin Privileges) — break-glass accounts (2-4) exist and are excluded from at
    /// least one MFA Conditional Access policy. Port of Invoke-CippTestE8_Admin_07. Reads Roles,
    /// RoleAssignmentScheduleInstances, Users, ConditionalAccessPolicies.
    /// </summary>
    public sealed class E8_Admin_07 : ICippTest
    {
        public string Id => "E8_Admin_07";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var roles = data.Get("Roles");
            var users = data.Get("Users");
            var ca = data.Get("ConditionalAccessPolicies");
            if (!CippTestHelpers.Any(roles) || !CippTestHelpers.Any(users) || !CippTestHelpers.Any(ca))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (Roles, Users or ConditionalAccessPolicies) not found.");
            }

            var gaRole = CippTestHelpers.Items(roles)
                .FirstOrDefault(r => CippTestHelpers.StrEq(r, "displayName", "Global Administrator"));
            if (gaRole.ValueKind != JsonValueKind.Object)
            {
                return new CippTestResult(TestStatus.Skipped, "Global Administrator role not found in the Roles cache.");
            }

            var gaTemplateId = CippTestHelpers.RoleTemplateId(gaRole);
            var gaUserIds = new HashSet<string>(StringComparer.Ordinal);
            foreach (var m in CippTestHelpers.Arr(gaRole, "members"))
            {
                var id = CippTestHelpers.Str(m, "id");
                if (!string.IsNullOrEmpty(id)) gaUserIds.Add(id!);
            }
            if (!string.IsNullOrEmpty(gaTemplateId))
            {
                foreach (var (roleDefId, principalId) in CippTestHelpers.ActiveRoleAssignments(data))
                {
                    if (string.Equals(roleDefId, gaTemplateId, StringComparison.OrdinalIgnoreCase))
                        gaUserIds.Add(principalId);
                }
            }

            var breakGlass = CippTestHelpers.Items(users)
                .Where(u => gaUserIds.Contains(CippTestHelpers.Str(u, "id") ?? "")
                    && CippTestHelpers.Like(CippTestHelpers.Str(u, "userPrincipalName"), "*onmicrosoft.com")
                    && CippTestHelpers.IsTrue(u, "accountEnabled"))
                .ToList();

            if (breakGlass.Count < 2)
            {
                return new CippTestResult(TestStatus.Failed,
                    $"Only {breakGlass.Count} Global Administrator(s) on the *.onmicrosoft.com domain. ACSC guidance recommends 2-4 dedicated cloud-only break-glass accounts.");
            }
            if (breakGlass.Count > 4)
            {
                return new CippTestResult(TestStatus.Failed,
                    $"{breakGlass.Count} cloud-only Global Administrators exist. Excessive break-glass accounts increase risk; reduce to 2-4.");
            }

            var breakGlassIds = new HashSet<string>(
                breakGlass.Select(u => CippTestHelpers.Str(u, "id") ?? "").Where(s => s.Length > 0), StringComparer.Ordinal);

            var withExclusion = CippTestHelpers.Items(ca).Where(p =>
                CippTestHelpers.StrEq(p, "state", "enabled") &&
                (CippTestHelpers.PathArrayContainsCi(p, "mfa", "grantControls", "builtInControls") ||
                 CippTestHelpers.PathTruthy(p, "grantControls", "authenticationStrength")) &&
                CippTestHelpers.PathArrayAnyIn(p, breakGlassIds, "conditions", "users", "excludeUsers")
            ).ToList();

            if (withExclusion.Count > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"{breakGlass.Count} break-glass account(s) found. They are excluded from {withExclusion.Count} MFA-enforcing Conditional Access policy/policies.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"{breakGlass.Count} break-glass account(s) exist but no MFA-enforcing Conditional Access policy excludes them. A token-service MFA outage will lock the tenant.");
        }
    }
}
