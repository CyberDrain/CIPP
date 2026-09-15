namespace CIPP.Tests
{
    /// <summary>CIS M365 (5.3.2) — 'Access reviews' for Guest Users SHALL be configured. Manual control (Informational).</summary>
    public sealed class CIS_5_3_2 : ICippTest
    {
        public string Id => "CIS_5_3_2";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
