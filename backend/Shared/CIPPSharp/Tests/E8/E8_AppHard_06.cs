namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (User Application Hardening) — ASR rule "Block credential stealing from LSASS" is
    /// enabled and assigned. Port of Invoke-CippTestE8_AppHard_06 (Test-E8AsrRule).
    /// </summary>
    public sealed class E8_AppHard_06 : ICippTest
    {
        public string Id => "E8_AppHard_06";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateAsrRule(data,
                "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockcredentialstealingfromwindowslocalsecurityauthoritysubsystem",
                "Block credential stealing from the Windows local security authority subsystem");
    }
}
