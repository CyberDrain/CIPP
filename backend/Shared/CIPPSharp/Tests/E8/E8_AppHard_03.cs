namespace CIPP.Tests
{
    /// <summary>E8 ML1 (User Application Hardening) — PDF viewers are configured securely. Manual task; always Informational. Port of Invoke-CippTestE8_AppHard_03.</summary>
    public sealed class E8_AppHard_03 : ICippTest
    {
        public string Id => "E8_AppHard_03";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm the standard organisation PDF viewer (Edge, Adobe Acrobat Reader, Foxit, etc.) is configured with Protected View / Sandbox enabled and JavaScript disabled. PDF viewer configuration is application-specific and not exposed via Graph; verify by reviewing the deployed Intune ADMX/Settings Catalog policy.");
    }
}
