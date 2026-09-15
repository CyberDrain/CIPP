using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (7.2.4) — OneDrive content sharing SHALL be restricted.
    /// Port of Invoke-CippTestCIS_7_2_4. Passes when OneDriveSharingCapability is one of
    /// Disabled / ExistingExternalUserSharingOnly / ExternalUserSharingOnly.
    /// </summary>
    public sealed class CIS_7_2_4 : ICippTest
    {
        public string Id => "CIS_7_2_4";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var spo = data.Get("SPOTenant");
            if (!Any(spo))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "SPOTenant cache not found. Please refresh the cache for this tenant.");
            }

            var cfg = FirstOrNull(spo)!.Value;
            var oneDrive = Str(cfg, "OneDriveSharingCapability");
            var sp = Str(cfg, "SharingCapability");

            if (InListCI(oneDrive, "Disabled", "ExistingExternalUserSharingOnly", "ExternalUserSharingOnly"))
            {
                return new CippTestResult(TestStatus.Passed,
                    $"OneDriveSharingCapability is restricted ({oneDrive}). SharePoint SharingCapability: {sp}.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"OneDriveSharingCapability is too permissive ({oneDrive}). Set to ExternalUserSharingOnly or more restrictive.");
        }
    }
}
