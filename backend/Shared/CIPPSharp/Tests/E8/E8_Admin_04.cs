using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Restrict Admin Privileges) — user consent for risky OAuth applications is restricted
    /// (ISM-1883). Port of Invoke-CippTestE8_Admin_04. Single source: AuthorizationPolicy (singleton).
    /// </summary>
    public sealed class E8_Admin_04 : ICippTest
    {
        public string Id => "E8_Admin_04";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var authPolicy = data.Get("AuthorizationPolicy");
            if (!CippTestHelpers.Any(authPolicy))
            {
                return new CippTestResult(TestStatus.Skipped, "AuthorizationPolicy cache not found.");
            }

            JsonElement cfg = default;
            foreach (var el in authPolicy.EnumerateArray()) { cfg = el; break; }
            CippTestHelpers.TryProp(cfg, "defaultUserRolePermissions", out var perms);

            var issues = new List<string>();
            if (CippTestHelpers.IsTrue(perms, "allowedToCreateApps"))
            {
                issues.Add("defaultUserRolePermissions.allowedToCreateApps is true — non-admin users can register new applications.");
            }
            if (CippTestHelpers.IsTrue(cfg, "allowUserConsentForRiskyApps"))
            {
                issues.Add("allowUserConsentForRiskyApps is true — users can consent to applications Microsoft flags as risky.");
            }
            if (CippTestHelpers.PathArrayContainsCi(cfg, "ManagePermissionGrantsForSelf.microsoft-user-default-legacy",
                    "permissionGrantPolicyIdsAssignedToDefaultUserRole"))
            {
                issues.Add("Legacy user consent policy in effect (`ManagePermissionGrantsForSelf.microsoft-user-default-legacy`). Switch to `microsoft-user-default-low` or admin-only.");
            }

            if (issues.Count == 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    "User consent for OAuth apps is restricted to low-impact (or admin-only).");
            }

            return new CippTestResult(TestStatus.Failed,
                "Risky OAuth consent configuration:\n\n" + string.Join("\n", issues.Select(i => "- " + i)));
        }
    }
}
