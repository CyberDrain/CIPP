namespace CIPP.Tests
{
    /// <summary>E8 ML2 (Configure Office Macros) — macros from the internet are blocked. Manual task; always Informational. Port of Invoke-CippTestE8_Macro_06.</summary>
    public sealed class E8_Macro_06 : ICippTest
    {
        public string Id => "E8_Macro_06";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm the *Block macros from running in Office files from the Internet* policy is set in the Office Cloud Policy Service (or the corresponding Microsoft Endpoint Manager Settings Catalog ADMX values for Word/Excel/PowerPoint/Visio/Outlook). The setting lives under each application's Trust Center.");
    }
}
