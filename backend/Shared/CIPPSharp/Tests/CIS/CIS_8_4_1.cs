using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (8.4.1) — App permission policies SHALL be configured.
    /// Port of Invoke-CippTestCIS_8_4_1. Reads the Global Teams app-permission policy; the effective
    /// third-party mode is GlobalCatalogAppsType, falling back to DefaultCatalogAppsType. Passes when
    /// the mode is BlockedAppList / AllowedAppList / BlockAllApps.
    /// </summary>
    public sealed class CIS_8_4_1 : ICippTest
    {
        public string Id => "CIS_8_4_1";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            if (!data.Has("CsTeamsAppPermissionPolicy"))
            {
                return new CippTestResult(TestStatus.Skipped, "CsTeamsAppPermissionPolicy cache not found.");
            }

            var g = FirstByIdentityOrFirst(data, "CsTeamsAppPermissionPolicy", "Global")!.Value;
            var thirdParty = Str(g, "GlobalCatalogAppsType") ?? Str(g, "DefaultCatalogAppsType");

            if (InListCI(thirdParty, "BlockedAppList", "AllowedAppList", "BlockAllApps"))
            {
                return new CippTestResult(TestStatus.Passed,
                    $"Teams App Permission Policy restricts third-party apps (mode: {thirdParty}).");
            }

            return new CippTestResult(TestStatus.Failed,
                $"Teams App Permission Policy allows all third-party apps (mode: {thirdParty}). Set to BlockedAppList, AllowedAppList, or BlockAllApps.");
        }
    }
}
