namespace CIPP.Tests
{
    /// <summary>CIS M365 (2.4.3) — Microsoft Defender for Cloud Apps SHALL be enabled and configured. Manual control (Informational).</summary>
    public sealed class CIS_2_4_3 : ICippTest
    {
        public string Id => "CIS_2_4_3";
        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational, "This is a task performed manually.");
    }
}
