namespace CIPP.Tests
{
    /// <summary>CIS M365 (2.2.1) — Emergency access account activity SHALL be monitored. Manual control (Informational).</summary>
    public sealed class CIS_2_2_1 : ICippTest
    {
        public string Id => "CIS_2_2_1";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
