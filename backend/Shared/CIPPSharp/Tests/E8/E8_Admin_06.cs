namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (Restrict Admin Privileges) — privileged access events are centrally logged (ISM-1509).
    /// Port of Invoke-CippTestE8_Admin_06. Manual/informational task; always Informational.
    /// </summary>
    public sealed class E8_Admin_06 : ICippTest
    {
        public string Id => "E8_Admin_06";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm Entra ID Sign-in and Audit logs (and Microsoft 365 Unified Audit Log) are forwarded to a SIEM (Sentinel, Splunk, etc.) and retained for at least 12 months. CIPP cannot verify diagnostic settings or external SIEM connectivity from the partner tenant.");
    }
}
