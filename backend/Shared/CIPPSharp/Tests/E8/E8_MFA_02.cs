using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (MFA) — a Conditional Access policy enforces MFA for all users on all cloud apps. Port
    /// of Invoke-CippTestE8_MFA_02. Single source: ConditionalAccessPolicies.
    /// </summary>
    public sealed class E8_MFA_02 : ICippTest
    {
        public string Id => "E8_MFA_02";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var ca = data.Get("ConditionalAccessPolicies");
            if (!CippTestHelpers.Any(ca))
            {
                return new CippTestResult(TestStatus.Skipped, "ConditionalAccessPolicies cache not found.");
            }

            var match = CippTestHelpers.Items(ca).Where(p =>
                CippTestHelpers.StrEq(p, "state", "enabled") &&
                CippTestHelpers.PathArrayContainsCi(p, "All", "conditions", "users", "includeUsers") &&
                CippTestHelpers.PathArrayContainsCi(p, "All", "conditions", "applications", "includeApplications") &&
                (CippTestHelpers.PathArrayContainsCi(p, "mfa", "grantControls", "builtInControls") ||
                 CippTestHelpers.PathTruthy(p, "grantControls", "authenticationStrength"))
            ).ToList();

            if (match.Count > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"{match.Count} Conditional Access policy/policies enforce MFA on all users for all cloud apps:\n\n"
                    + CippTestHelpers.BulletDisplayNames(match));
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy targets All Users + All Cloud Apps with an MFA grant control.");
        }
    }
}
