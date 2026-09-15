namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (Configure Office Macros) — ASR rule "Block Office communication application from
    /// creating child processes" is enabled and assigned. Port of Invoke-CippTestE8_Macro_05 (Test-E8AsrRule).
    /// </summary>
    public sealed class E8_Macro_05 : ICippTest
    {
        public string Id => "E8_Macro_05";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateAsrRule(data,
                "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficecommunicationappfromcreatingchildprocesses",
                "Block Office communication application from creating child processes");
    }
}
