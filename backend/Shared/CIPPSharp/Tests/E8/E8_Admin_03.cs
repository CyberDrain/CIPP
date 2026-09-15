using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Restrict Admin Privileges) — Conditional Access requires a compliant or hybrid-joined
    /// device for privileged role sign-ins. Port of Invoke-CippTestE8_Admin_03. Reads
    /// ConditionalAccessPolicies + privileged Roles (CA includeRoles reference role template ids).
    /// </summary>
    public sealed class E8_Admin_03 : ICippTest
    {
        public string Id => "E8_Admin_03";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var ca = data.Get("ConditionalAccessPolicies");
            var privRoles = CippTestHelpers.PrivilegedRoles(data);
            if (!CippTestHelpers.Any(ca) || privRoles.Count == 0)
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (ConditionalAccessPolicies or Roles) not found.");
            }

            var privRoleIds = CippTestHelpers.TemplateIdSet(privRoles);
            var match = CippTestHelpers.Items(ca).Where(p =>
                CippTestHelpers.StrEq(p, "state", "enabled") &&
                CippTestHelpers.PathArrayAnyIn(p, privRoleIds, "conditions", "users", "includeRoles") &&
                (CippTestHelpers.PathArrayContainsCi(p, "compliantDevice", "grantControls", "builtInControls") ||
                 CippTestHelpers.PathArrayContainsCi(p, "domainJoinedDevice", "grantControls", "builtInControls"))
            ).ToList();

            if (match.Count > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"{match.Count} Conditional Access policy/policies require a compliant/domain-joined device for privileged role sign-ins:\n\n"
                    + CippTestHelpers.BulletDisplayNames(match));
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy targets privileged roles with a *Require compliant device* or *Require hybrid Azure AD joined device* grant. Privileged accounts may sign in from unmanaged endpoints.");
        }
    }
}
