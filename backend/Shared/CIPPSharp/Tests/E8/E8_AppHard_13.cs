namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML3 (User Application Hardening) — ASR rule "Block persistence through WMI event
    /// subscription" is enabled and assigned. Port of Invoke-CippTestE8_AppHard_13 (Test-E8AsrRule).
    /// </summary>
    public sealed class E8_AppHard_13 : ICippTest
    {
        public string Id => "E8_AppHard_13";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateAsrRule(data,
                "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockpersistencethroughwmieventsubscription",
                "Block persistence through WMI event subscription");
    }
}
