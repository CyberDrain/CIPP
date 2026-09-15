using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (MFA) — legacy authentication is blocked tenant-wide. Port of Invoke-CippTestE8_MFA_03.
    /// Single source: ConditionalAccessPolicies.
    /// </summary>
    public sealed class E8_MFA_03 : ICippTest
    {
        public string Id => "E8_MFA_03";

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
                (CippTestHelpers.PathArrayContainsCi(p, "exchangeActiveSync", "conditions", "clientAppTypes") ||
                 CippTestHelpers.PathArrayContainsCi(p, "other", "conditions", "clientAppTypes")) &&
                CippTestHelpers.PathArrayContainsCi(p, "block", "grantControls", "builtInControls")
            ).ToList();

            if (match.Count > 0)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"{match.Count} Conditional Access policy/policies block legacy auth:\n\n"
                    + CippTestHelpers.BulletDisplayNames(match));
            }

            return new CippTestResult(TestStatus.Failed,
                "No enabled Conditional Access policy blocks legacy authentication clients (`exchangeActiveSync`/`other`). MFA can be bypassed via legacy protocols if not blocked.");
        }
    }
}
