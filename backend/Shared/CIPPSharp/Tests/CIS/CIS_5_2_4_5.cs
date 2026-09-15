namespace CIPP.Tests
{
    /// <summary>CIS M365 (5.2.4.5) — All admins SHALL be notified when other admins reset their password. Manual control (Informational).</summary>
    public sealed class CIS_5_2_4_5 : ICippTest
    {
        public string Id => "CIS_5_2_4_5";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a manual control. Verify in the Microsoft Entra admin center > Entra ID > Password reset > Notifications that 'Notify all admins when other admins reset their password' is set to Yes.");
    }
}
