namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.2.5) — The option to remain signed in SHALL be hidden (manual).
    /// Port of Invoke-CippTestCIS_5_1_2_5 — always Informational.
    /// </summary>
    public sealed class CIS_5_1_2_5 : ICippTest
    {
        public string Id => "CIS_5_1_2_5";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
