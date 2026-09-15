namespace CIPP.Tests
{
    /// <summary>CIS M365 (5.2.4.4) — Users SHALL be notified on password resets. Manual control (Informational).</summary>
    public sealed class CIS_5_2_4_4 : ICippTest
    {
        public string Id => "CIS_5_2_4_4";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a manual control. Verify in the Microsoft Entra admin center > Entra ID > Password reset > Notifications that 'Notify users on password resets' is set to Yes.");
    }
}
