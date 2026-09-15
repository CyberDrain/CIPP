using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (7.2.3) — External content sharing SHALL be restricted.
    /// Port of Invoke-CippTestCIS_7_2_3. Passes when the tenant SharingCapability is one of
    /// Disabled / ExistingExternalUserSharingOnly / ExternalUserSharingOnly.
    /// </summary>
    public sealed class CIS_7_2_3 : ICippTest
    {
        public string Id => "CIS_7_2_3";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var spo = data.Get("SPOTenant");
            if (!Any(spo))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "SPOTenant cache not found. Please refresh the cache for this tenant.");
            }

            var cfg = FirstOrNull(spo)!.Value;
            var cap = Str(cfg, "SharingCapability");

            if (InListCI(cap, "Disabled", "ExistingExternalUserSharingOnly", "ExternalUserSharingOnly"))
            {
                return new CippTestResult(TestStatus.Passed,
                    $"SharePoint SharingCapability is restricted ({cap}).");
            }

            return new CippTestResult(TestStatus.Failed,
                $"SharePoint SharingCapability is too permissive ({cap}). Set to ExternalUserSharingOnly or more restrictive.");
        }
    }
}
