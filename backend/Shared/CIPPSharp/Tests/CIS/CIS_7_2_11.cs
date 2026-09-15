using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (7.2.11) — The SharePoint default sharing link permission SHALL be set.
    /// Port of Invoke-CippTestCIS_7_2_11. The CSOM cache stores DefaultLinkPermission as the numeric
    /// SharingPermissionType (None=0, View=1, Edit=2); normalise before comparing. Passes when View.
    /// </summary>
    public sealed class CIS_7_2_11 : ICippTest
    {
        public string Id => "CIS_7_2_11";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var spo = data.Get("SPOTenant");
            if (!Any(spo))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "SPOTenant cache not found. Please refresh the cache for this tenant.");
            }

            var cfg = FirstOrNull(spo)!.Value;
            var raw = Cell(Prop(cfg, "DefaultLinkPermission"));
            var permission = raw switch
            {
                "0" => "None",
                "1" => "View",
                "2" => "Edit",
                _ => raw,
            };

            if (string.Equals(permission, "View", System.StringComparison.OrdinalIgnoreCase))
            {
                return new CippTestResult(TestStatus.Passed, "DefaultLinkPermission is set to View.");
            }

            return new CippTestResult(TestStatus.Failed,
                $"DefaultLinkPermission is set to {permission}. CIS requires View.");
        }
    }
}
