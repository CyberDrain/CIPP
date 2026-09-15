namespace CIPP.Tests
{
    /// <summary>CIS M365 (5.2.4.3) — SSPR registration and authentication re-confirmation SHALL be required. Manual control (Informational).</summary>
    public sealed class CIS_5_2_4_3 : ICippTest
    {
        public string Id => "CIS_5_2_4_3";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a manual control. Verify in the Microsoft Entra admin center > Entra ID > Password reset > Registration that 'Require users to register when signing in' is Yes and re-confirmation of authentication information is required on a defined cadence.");
    }
}
