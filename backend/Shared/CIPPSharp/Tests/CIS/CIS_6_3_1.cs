namespace CIPP.Tests
{
    /// <summary>CIS M365 (6.3.1) — Users installing Outlook add-ins SHALL NOT be allowed. Manual control (Informational).</summary>
    public sealed class CIS_6_3_1 : ICippTest
    {
        public string Id => "CIS_6_3_1";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
