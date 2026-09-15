namespace CIPP.Tests
{
    /// <summary>E8 ML2 (Application Control) — allowlist covers all executable types (ISM-0843). Manual task; always Informational. Port of Invoke-CippTestE8_AppCtrl_02.</summary>
    public sealed class E8_AppCtrl_02 : ICippTest
    {
        public string Id => "E8_AppCtrl_02";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm WDAC/AppLocker rules cover executables, software libraries (DLLs/OCX), scripts (PS1, JS, VBS), installers (MSI/MSIX), compiled HTML, HTA, control panel applets, and drivers. The full rule contents are stored as XML inside Intune profiles which are not easily summarised; review the deployed policy in Intune.");
    }
}
