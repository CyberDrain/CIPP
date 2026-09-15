namespace CIPP.Tests
{
    /// <summary>E8 ML3 (Configure Office Macros) — macros are scanned by anti-virus software. Manual task; always Informational. Port of Invoke-CippTestE8_Macro_07.</summary>
    public sealed class E8_Macro_07 : ICippTest
    {
        public string Id => "E8_Macro_07";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm the Office *Macro Runtime Scan Scope* policy is set to *Enable for all documents* and that Microsoft Defender Antivirus AMSI is enabled on all Windows endpoints. AMSI integration with Office macros is on by default on supported builds; this control is verified by inspecting Defender + Office configuration which is not exposed via Graph in a deterministic way.");
    }
}
