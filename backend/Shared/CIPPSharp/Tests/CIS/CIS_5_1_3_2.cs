namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.3.2) — Restrict user ability to access groups features in My Groups (manual).
    /// Port of Invoke-CippTestCIS_5_1_3_2 — always Informational.
    /// </summary>
    public sealed class CIS_5_1_3_2 : ICippTest
    {
        public string Id => "CIS_5_1_3_2";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a manual control. Verify in the Microsoft Entra admin center > Entra ID > Groups > General that, under Self Service Group Management, \"Restrict user ability to access groups features in My Groups\" is set to Yes.");
    }
}
