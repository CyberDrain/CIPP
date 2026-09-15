using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.5.1) — User consent to apps accessing company data SHALL NOT be allowed.
    /// Port of Invoke-CippTestCIS_5_1_5_1. Single source: AuthorizationPolicy (first record).
    /// Failed only when the legacy permission-grant policy is assigned; Passed otherwise.
    /// </summary>
    public sealed class CIS_5_1_5_1 : ICippTest
    {
        public string Id => "CIS_5_1_5_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var auth = data.Get("AuthorizationPolicy");
            if (!Any(auth))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "AuthorizationPolicy cache not found. Please refresh the cache for this tenant.");
            }

            var cfg = FirstOrNull(auth)!.Value;
            var consentPolicies = PropPath(cfg, "defaultUserRolePermissions.permissionGrantPoliciesAssigned");
            string joined = JoinCsv(consentPolicies);

            // PS Passed unless the list contains the legacy policy.
            bool hasLegacy = ContainsCI(consentPolicies, "ManagePermissionGrantsForSelf.microsoft-user-default-legacy");

            if (!hasLegacy)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"User consent to apps is restricted. Permission grant policies: {joined}");
            }

            return new CippTestResult(TestStatus.Failed,
                $"User consent to apps is open (legacy policy assigned). Permission grant policies: {joined}");
        }
    }
}
