namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Configure Office Macros) — ASR rule "Block Win32 API calls from Office macros" is
    /// enabled and assigned. Port of Invoke-CippTestE8_Macro_01 (Test-E8AsrRule).
    /// </summary>
    public sealed class E8_Macro_01 : ICippTest
    {
        public string Id => "E8_Macro_01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateAsrRule(data,
                "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockwin32apicallsfromofficemacros",
                "Block Win32 API calls from Office macros");
    }
}
