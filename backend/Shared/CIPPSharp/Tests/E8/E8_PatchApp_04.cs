namespace CIPP.Tests
{
    /// <summary>E8 ML3 (Patch Applications) — unsupported applications are removed (ISM-1467). Manual task; always Informational. Port of Invoke-CippTestE8_PatchApp_04.</summary>
    public sealed class E8_PatchApp_04 : ICippTest
    {
        public string Id => "E8_PatchApp_04";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Identify and remove applications that are no longer supported by the vendor (e.g. Office 2016/2019 past support, Adobe Reader 11, Java 8 unpatched, Flash). Use the Intune Discovered Apps inventory or Defender Vulnerability Management software inventory to enumerate.");
    }
}
