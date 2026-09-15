namespace CIPP.Tests
{
    /// <summary>E8 ML2 (Application Control) — Microsoft recommended driver block list is implemented. Manual task; always Informational. Port of Invoke-CippTestE8_AppCtrl_04.</summary>
    public sealed class E8_AppCtrl_04 : ICippTest
    {
        public string Id => "E8_AppCtrl_04";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm the Microsoft Vulnerable Driver Blocklist is enabled via *Memory Integrity / Core Isolation*, or via WDAC driver block XML. From Windows 11 22H2 the blocklist is on by default when Memory Integrity is enabled; verify in Settings catalog under *Defender > Allow Memory Integrity*.");
    }
}
