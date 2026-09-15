namespace CIPP.Tests
{
    /// <summary>CIS M365 (2.1.13) — Connection filter safe list SHALL be off. Manual control (Informational).</summary>
    public sealed class CIS_2_1_13 : ICippTest
    {
        public string Id => "CIS_2_1_13";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
