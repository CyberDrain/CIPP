namespace CIPP.Tests
{
    /// <summary>CIS M365 (2.4.1) — Priority account protection SHALL be enabled and configured. Manual control (Informational).</summary>
    public sealed class CIS_2_4_1 : ICippTest
    {
        public string Id => "CIS_2_4_1";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
