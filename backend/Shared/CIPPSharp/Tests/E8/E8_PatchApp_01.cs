namespace CIPP.Tests
{
    /// <summary>E8 ML1 (Patch Applications) — Office and supported applications use automatic updates. Manual task; always Informational. Port of Invoke-CippTestE8_PatchApp_01.</summary>
    public sealed class E8_PatchApp_01 : ICippTest
    {
        public string Id => "E8_PatchApp_01";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm Microsoft 365 Apps is set to a current channel (Current/Monthly Enterprise) with automatic updates, and that browsers (Edge, Chrome, Firefox) and PDF viewers self-update. Office update channel can be enforced via Office Cloud Policy *UpdateChannel*; Edge auto-update via *UpdateDefault*.");
    }
}
