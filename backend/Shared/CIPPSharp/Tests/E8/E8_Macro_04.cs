namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (Configure Office Macros) — ASR rule "Block Office applications from injecting code
    /// into other processes" is enabled and assigned. Port of Invoke-CippTestE8_Macro_04 (Test-E8AsrRule).
    /// </summary>
    public sealed class E8_Macro_04 : ICippTest
    {
        public string Id => "E8_Macro_04";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateAsrRule(data,
                "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficeapplicationsfrominjectingcodeintootherprocesses",
                "Block Office applications from injecting code into other processes");
    }
}
