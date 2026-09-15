using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML3 (MFA) — phishing-resistant authentication strength is required for all users. Port of
    /// Invoke-CippTestE8_MFA_10. Single source: ConditionalAccessPolicies. Matches the built-in
    /// Phishing-resistant MFA authentication strength (id 00000000-0000-0000-0000-000000000004).
    /// </summary>
    public sealed class E8_MFA_10 : ICippTest
    {
        private const string PhishResistantId = "00000000-0000-0000-0000-000000000004";

        public string Id => "E8_MFA_10";

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
                CippTestHelpers.PathTruthy(p, "grantControls", "authenticationStrength") &&
                string.Equals(CippTestHelpers.PathStr(p, "grantControls", "authenticationStrength", "id"),
                    PhishResistantId, StringComparison.OrdinalIgnoreCase)
            ).ToList();

            if (match.Count > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"{match.Count} Conditional Access policy/policies enforce phishing-resistant MFA tenant-wide:\n\n"
                    + CippTestHelpers.BulletDisplayNames(match));
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy enforces the *Phishing-resistant MFA* authentication strength on All Users + All Cloud Apps.");
        }
    }
}
