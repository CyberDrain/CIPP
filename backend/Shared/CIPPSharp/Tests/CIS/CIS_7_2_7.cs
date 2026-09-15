using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (7.2.7) — Link sharing SHALL be restricted in SharePoint and OneDrive.
    /// Port of Invoke-CippTestCIS_7_2_7. The CSOM cache stores DefaultSharingLinkType as the numeric
    /// SharingLinkType (None=0, Direct=1, Internal=2, AnonymousAccess=3); normalise before comparing.
    /// Passes when the effective type is Direct or Internal.
    /// </summary>
    public sealed class CIS_7_2_7 : ICippTest
    {
        public string Id => "CIS_7_2_7";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var spo = data.Get("SPOTenant");
            if (!Any(spo))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "SPOTenant cache not found. Please refresh the cache for this tenant.");
            }

            var cfg = FirstOrNull(spo)!.Value;
            var raw = Cell(Prop(cfg, "DefaultSharingLinkType"));
            var linkType = raw switch
            {
                "0" => "None",
                "1" => "Direct",
                "2" => "Internal",
                "3" => "AnonymousAccess",
                _ => raw,
            };

            if (InListCI(linkType, "Direct", "Internal"))
            {
                return new CippTestResult(TestStatus.Passed,
                    $"DefaultSharingLinkType is restricted ({linkType}).");
            }

            return new CippTestResult(TestStatus.Failed,
                $"DefaultSharingLinkType is too permissive ({linkType}). Set to Direct or Internal.");
        }
    }
}
