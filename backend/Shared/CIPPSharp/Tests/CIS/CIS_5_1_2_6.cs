namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.2.6) — 'LinkedIn account connections' SHALL be disabled (manual).
    /// Port of Invoke-CippTestCIS_5_1_2_6 — always Informational.
    /// </summary>
    public sealed class CIS_5_1_2_6 : ICippTest
    {
        public string Id => "CIS_5_1_2_6";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
