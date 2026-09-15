using static CIPP.Tests.CippTestHelpers;

namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (7.2.6) — SharePoint external sharing SHALL be restricted.
    /// Port of Invoke-CippTestCIS_7_2_6. Passes when sharing is Disabled, or restricted to an
    /// allow-list / block-list of domains that is actually populated.
    /// </summary>
    public sealed class CIS_7_2_6 : ICippTest
    {
        public string Id => "CIS_7_2_6";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
        {
            var spo = data.Get("SPOTenant");
            if (!Any(spo))
            {
                return new CippTestResult(TestStatus.Skipped,
                    "SPOTenant cache not found. Please refresh the cache for this tenant.");
            }

            var cfg = FirstOrNull(spo)!.Value;
            var capability = Str(cfg, "SharingCapability");
            var mode = Str(cfg, "SharingDomainRestrictionMode");

            bool pass = StrEq(cfg, "SharingCapability", "Disabled")
                || (StrEq(cfg, "SharingDomainRestrictionMode", "AllowList") && HasNonBlankField(cfg, "SharingAllowedDomainList"))
                || (StrEq(cfg, "SharingDomainRestrictionMode", "BlockList") && HasNonBlankField(cfg, "SharingBlockedDomainList"));

            if (pass)
            {
                var msg = StrEq(cfg, "SharingCapability", "Disabled")
                    ? "External sharing is fully disabled (SharingCapability: Disabled)."
                    : $"External sharing is restricted by domain list (mode: {mode}).";
                return new CippTestResult(TestStatus.Passed, msg);
            }

            return new CippTestResult(TestStatus.Failed,
                $"External sharing is not restricted (SharingCapability: {capability}, SharingDomainRestrictionMode: {mode}).");
        }
    }
}
