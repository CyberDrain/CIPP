namespace CIPP.Tests
{
    /// <summary>E8 ML3 (Application Control) — event logs are centrally collected. Manual task; always Informational. Port of Invoke-CippTestE8_AppCtrl_05.</summary>
    public sealed class E8_AppCtrl_05 : ICippTest
    {
        public string Id => "E8_AppCtrl_05";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm WDAC / AppLocker event logs (Microsoft-Windows-CodeIntegrity, Microsoft-Windows-AppLocker) are forwarded to a SIEM (Sentinel via the Windows Security Events connector or Defender for Endpoint AdvancedHunting).");
    }
}
