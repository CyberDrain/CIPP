namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML3 (User Application Hardening) — ASR rule "Block abuse of exploited vulnerable signed
    /// drivers" is enabled and assigned. Port of Invoke-CippTestE8_AppHard_12 (Test-E8AsrRule).
    /// </summary>
    public sealed class E8_AppHard_12 : ICippTest
    {
        public string Id => "E8_AppHard_12";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateAsrRule(data,
                "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockabuseofexploitedvulnerablesigneddrivers",
                "Block abuse of exploited vulnerable signed drivers");
    }
}
