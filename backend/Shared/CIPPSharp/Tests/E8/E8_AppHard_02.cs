namespace CIPP.Tests
{
    /// <summary>E8 ML1 (User Application Hardening) — Internet Explorer 11 is disabled or removed (ISM-1666). Manual task; always Informational. Port of Invoke-CippTestE8_AppHard_02.</summary>
    public sealed class E8_AppHard_02 : ICippTest
    {
        public string Id => "E8_AppHard_02";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. IE11 has been retired by Microsoft, but the legacy MSHTML engine and IE mode still exist on Windows. Confirm IE11 desktop is disabled via the *DisableInternetExplorerApp* policy and that any IE-mode site list is curated. CIPP cannot verify per-device installation state of legacy components from Graph.");
    }
}
