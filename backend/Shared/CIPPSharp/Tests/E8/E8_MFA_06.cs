using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (MFA) — phishing-resistant authentication strength is required for privileged roles.
    /// Port of Invoke-CippTestE8_MFA_06. Reads ConditionalAccessPolicies + privileged Roles (CA
    /// includeRoles reference role template ids).
    /// </summary>
    public sealed class E8_MFA_06 : ICippTest
    {
        private const string PhishResistantId = "00000000-0000-0000-0000-000000000004";

        public string Id => "E8_MFA_06";

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
                CippTestHelpers.PathTruthy(p, "grantControls", "authenticationStrength") &&
                string.Equals(CippTestHelpers.PathStr(p, "grantControls", "authenticationStrength", "id"),
                    PhishResistantId, StringComparison.OrdinalIgnoreCase)
            ).ToList();

            if (match.Count > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"{match.Count} Conditional Access policy/policies require phishing-resistant MFA for privileged roles:\n\n"
                    + CippTestHelpers.BulletDisplayNames(match));
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy targets privileged roles with the built-in *Phishing-resistant MFA* authentication strength.");
        }
    }
}
