namespace CIPP.Tests
{
    /// <summary>E8 ML1 (User Application Hardening) — Windows PowerShell 2.0 is removed (ISM-1622). Manual task; always Informational. Port of Invoke-CippTestE8_AppHard_05.</summary>
    public sealed class E8_AppHard_05 : ICippTest
    {
        public string Id => "E8_AppHard_05";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm the Windows optional feature *MicrosoftWindowsPowerShellV2* is removed from all Windows endpoints. PowerShell 2.0 lacks AMSI and ScriptBlockLogging. Verify with an Intune compliance script (Get-WindowsOptionalFeature -FeatureName MicrosoftWindowsPowerShellV2*).");
    }
}
