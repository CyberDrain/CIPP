namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML3 (User Application Hardening) — ASR rule "Block untrusted/unsigned processes from USB"
    /// is enabled and assigned. Port of Invoke-CippTestE8_AppHard_10 (Test-E8AsrRule).
    /// </summary>
    public sealed class E8_AppHard_10 : ICippTest
    {
        public string Id => "E8_AppHard_10";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateAsrRule(data,
                "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockuntrustedunsignedprocessesthatrunfromusb",
                "Block untrusted and unsigned processes that run from USB");
    }
}
