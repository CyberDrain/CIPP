namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (User Application Hardening) — ASR rule "Block JS/VBS launching downloaded executable
    /// content" is enabled and assigned. Port of Invoke-CippTestE8_AppHard_09 (Test-E8AsrRule).
    /// </summary>
    public sealed class E8_AppHard_09 : ICippTest
    {
        public string Id => "E8_AppHard_09";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateAsrRule(data,
                "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockjavascriptorvbscriptfromlaunchingdownloadedexecutablecontent",
                "Block JavaScript or VBScript from launching downloaded executable content");
    }
}
