namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (User Application Hardening) — ASR rule "Block executable content from email and
    /// webmail" is enabled and assigned. Port of Invoke-CippTestE8_AppHard_07 (Test-E8AsrRule).
    /// </summary>
    public sealed class E8_AppHard_07 : ICippTest
    {
        public string Id => "E8_AppHard_07";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateAsrRule(data,
                "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockexecutablecontentfromemailclientandwebmail",
                "Block executable content from email client and webmail");
    }
}
