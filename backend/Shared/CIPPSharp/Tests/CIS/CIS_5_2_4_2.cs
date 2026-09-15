namespace CIPP.Tests
{
    /// <summary>CIS M365 (5.2.4.2) — Two methods SHALL be required for password reset. Manual control (Informational).</summary>
    public sealed class CIS_5_2_4_2 : ICippTest
    {
        public string Id => "CIS_5_2_4_2";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a manual control. Verify in the Microsoft Entra admin center > Entra ID > Password reset > Authentication methods that the Number of methods required to reset is set to 2.");
    }
}
