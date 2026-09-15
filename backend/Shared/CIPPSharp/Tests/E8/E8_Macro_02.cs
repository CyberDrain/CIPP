namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Configure Office Macros) — ASR rule "Block Office applications from creating
    /// executable content" is enabled and assigned. Port of Invoke-CippTestE8_Macro_02 (Test-E8AsrRule).
    /// </summary>
    public sealed class E8_Macro_02 : ICippTest
    {
        public string Id => "E8_Macro_02";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => CippTestHelpers.EvaluateAsrRule(data,
                "device_vendor_msft_policy_config_defender_attacksurfacereductionrules_blockofficeapplicationsfromcreatingexecutablecontent",
                "Block Office applications from creating executable content");
    }
}
