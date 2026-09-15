namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML3 (User Application Hardening) — ASR rule "Block process creations from PsExec and WMI
    /// commands" is enabled and assigned. Port of Invoke-CippTestE8_AppHard_11 (Test-E8AsrRule).
    /// </summary>
    public sealed class E8_AppHard_11 : ICippTest
    {
        public string Id => "E8_AppHard_11";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateAsrRule(data,
                "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockprocesscreationsfrompsexecandwmicommands",
                "Block process creations originating from PsExec and WMI commands");
    }
}
