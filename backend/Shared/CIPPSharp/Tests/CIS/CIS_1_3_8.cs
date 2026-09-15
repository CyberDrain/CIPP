namespace CIPP.Tests
{
    /// <summary>CIS M365 (1.3.8) — Sways SHALL NOT be shared externally. Manual control (Informational).</summary>
    public sealed class CIS_1_3_8 : ICippTest
    {
        public string Id => "CIS_1_3_8";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
