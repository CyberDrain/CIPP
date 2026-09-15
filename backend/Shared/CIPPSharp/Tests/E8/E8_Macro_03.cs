namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Configure Office Macros) — ASR rule "Block all Office applications from creating
    /// child processes" is enabled and assigned. Port of Invoke-CippTestE8_Macro_03 (Test-E8AsrRule).
    /// </summary>
    public sealed class E8_Macro_03 : ICippTest
    {
        public string Id => "E8_Macro_03";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateAsrRule(data,
                "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockallofficeapplicationsfromcreatingchildprocesses",
                "Block all Office applications from creating child processes");
    }
}
