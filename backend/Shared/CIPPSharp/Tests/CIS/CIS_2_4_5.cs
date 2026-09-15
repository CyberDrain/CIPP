namespace CIPP.Tests
{
    /// <summary>CIS M365 (2.4.5) — 'AIR' remediation SHALL be enabled. Manual control (Informational).</summary>
    public sealed class CIS_2_4_5 : ICippTest
    {
        public string Id => "CIS_2_4_5";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a manual control. Verify in the Microsoft Defender portal > Settings > Endpoints (or Email & collaboration policies) that Automated Investigation and Response (AIR) remediation is enabled.");
    }
}
