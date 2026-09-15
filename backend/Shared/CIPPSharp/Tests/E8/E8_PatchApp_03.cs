namespace CIPP.Tests
{
    /// <summary>E8 ML2 (Patch Applications) — vulnerable applications are patched within 48 hours of an exploit becoming public. Manual task; always Informational. Port of Invoke-CippTestE8_PatchApp_03.</summary>
    public sealed class E8_PatchApp_03 : ICippTest
    {
        public string Id => "E8_PatchApp_03";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Use Microsoft Defender Vulnerability Management (or the Intune Discovered Apps inventory) to triage applications with known CVEs. Patch internet-facing apps within 48 hours of an exploit being known and within 2 weeks otherwise. Determining \"critical\" CVE status programmatically requires Defender Vulnerability Management licensing and is not surfaced in the local cache.");
    }
}
