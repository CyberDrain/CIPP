namespace CIPP.Tests
{
    /// <summary>E8 ML1 (User Application Hardening) — legacy .NET Framework 3.5/2.0 is removed (ISM-1655). Manual task; always Informational. Port of Invoke-CippTestE8_AppHard_04.</summary>
    public sealed class E8_AppHard_04 : ICippTest
    {
        public string Id => "E8_AppHard_04";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm .NET Framework 3.5 (which includes 2.0 and 3.0) is uninstalled or never installed on standard SOEs. CIPP can list detected applications via the Intune Discovered Apps inventory but the optional Windows feature state is not surfaced; verify with an Intune Compliance Policy or PowerShell script (Get-WindowsOptionalFeature -FeatureName NetFx3).");
    }
}
