namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.2.4) — Access to the Entra admin center SHALL be restricted (manual).
    /// Port of Invoke-CippTestCIS_5_1_2_4 — always Informational.
    /// </summary>
    public sealed class CIS_5_1_2_4 : ICippTest
    {
        public string Id => "CIS_5_1_2_4";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
