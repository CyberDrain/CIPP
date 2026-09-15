namespace CIPP.Tests
{
    /// <summary>CIS M365 (5.3.3) — 'Access reviews' for privileged roles SHALL be configured. Manual control (Informational).</summary>
    public sealed class CIS_5_3_3 : ICippTest
    {
        public string Id => "CIS_5_3_3";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
