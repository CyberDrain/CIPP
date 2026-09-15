namespace CIPP.Tests
{
    /// <summary>CIS M365 (2.1.12) — Connection filter IP allow list SHALL NOT be used. Manual control (Informational).</summary>
    public sealed class CIS_2_1_12 : ICippTest
    {
        public string Id => "CIS_2_1_12";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
