namespace CIPP.Tests
{
    /// <summary>CIS M365 (7.2.8) — External sharing SHALL be restricted by security group. Manual control (Informational).</summary>
    public sealed class CIS_7_2_8 : ICippTest
    {
        public string Id => "CIS_7_2_8";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
