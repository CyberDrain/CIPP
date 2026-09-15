namespace CIPP.Tests
{
    /// <summary>CIS M365 (5.2.4.1) — 'Self service password reset enabled' SHALL be set to 'All'. Manual control (Informational).</summary>
    public sealed class CIS_5_2_4_1 : ICippTest
    {
        public string Id => "CIS_5_2_4_1";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
