namespace CIPP.Tests
{
    /// <summary>E8 ML2 (Application Control) — Microsoft recommended block list is implemented. Manual task; always Informational. Port of Invoke-CippTestE8_AppCtrl_03.</summary>
    public sealed class E8_AppCtrl_03 : ICippTest
    {
        public string Id => "E8_AppCtrl_03";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm Microsoft's **recommended block rules** (LOLBins such as bash, bginfo, cdb, msbuild, powershell_ise.exe, etc.) are deployed via WDAC. The block list is published as XML at `https://aka.ms/wdac-block-rules` and is delivered through an Intune WDAC policy XML file.");
    }
}
