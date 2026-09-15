using System.Text.Json;
using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (8.2.1) — External domains SHALL be restricted in the Teams admin center.
    /// Port of Invoke-CippTestCIS_8_2_1. Joins CsExternalAccessPolicy + CsTenantFederationConfiguration.
    /// Passes when federation is disabled by policy, disabled tenant-wide, or restricted to an allow-list.
    /// </summary>
    public sealed class CIS_8_2_1 : ICippTest
    {
        public string Id => "CIS_8_2_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var external = data.Get("CsExternalAccessPolicy");
            var federation = data.Get("CsTenantFederationConfiguration");

            if (!Any(external) && !Any(federation))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "Required cache (CsExternalAccessPolicy or CsTenantFederationConfiguration) not found. Please refresh the cache for this tenant.");
            }

            var e = FirstOrNull(external);
            var f = FirstOrNull(federation);

            bool policyDisabled = e.HasValue && IsFalse(e.Value, "EnableFederationAccess");
            bool tenantDisabled = f.HasValue && IsFalse(f.Value, "AllowFederatedUsers");

            bool tenantAllowList = false;
            if (f.HasValue && TryProp(f.Value, "AllowedDomains", out var ad) && PsTruthy(ad))
            {
                bool subAllowList = TryProp(ad, "AllowList", out var al) && PsTruthy(al);
                bool subAllowedDomain = TryProp(ad, "AllowedDomain", out var adn) && PsTruthy(adn);
                bool subArray = ad.ValueKind == JsonValueKind.Array && ad.GetArrayLength() > 0;
                tenantAllowList = subAllowList || subAllowedDomain || subArray;
            }

            var eFed = e.HasValue ? Cell(Prop(e.Value, "EnableFederationAccess")) : "";
            var fFed = f.HasValue ? Cell(Prop(f.Value, "AllowFederatedUsers")) : "";

            if (policyDisabled || tenantDisabled || tenantAllowList)
            {
                return new CippTestResult(TestStatus.Passed,
                    $"External domains are restricted.\n\n- EnableFederationAccess (policy): {eFed}\n- AllowFederatedUsers (tenant): {fFed}");
            }

            return new CippTestResult(TestStatus.Failed,
                $"External domains are not restricted.\n\n- EnableFederationAccess (policy): {eFed}\n- AllowFederatedUsers (tenant): {fFed}");
        }
    }
}
