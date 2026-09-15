namespace CIPP.Tests
{
    /// <summary>
    /// CIS M365 (5.1.3.3) — Owners can manage group membership requests in My Groups (manual).
    /// Port of Invoke-CippTestCIS_5_1_3_3 — always Informational.
    /// </summary>
    public sealed class CIS_5_1_3_3 : ICippTest
    {
        public string Id => "CIS_5_1_3_3";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a manual control. Verify in the Microsoft Entra admin center > Entra ID > Groups > General that \"Owners can manage group membership requests in My Groups\" is set to No.");
    }
}
