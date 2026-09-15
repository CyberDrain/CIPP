namespace CIPP.Tests
{
    /// <summary>CIS M365 (2.4.4) — Zero-hour auto purge for Microsoft Teams SHALL be on. Manual control (Informational).</summary>
    public sealed class CIS_2_4_4 : ICippTest
    {
        public string Id => "CIS_2_4_4";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
