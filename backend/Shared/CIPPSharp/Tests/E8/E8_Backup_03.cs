namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Regular Backups) — OneDrive Known Folder Move (KFM) is enforced. Port of
    /// Invoke-CippTestE8_Backup_03. Manual/informational task; always Informational.
    /// </summary>
    public sealed class E8_Backup_03 : ICippTest
    {
        public string Id => "E8_Backup_03";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm OneDrive Known Folder Move is configured to redirect Desktop, Documents, and Pictures to OneDrive on all Windows endpoints. Configure via Intune Settings catalog: *OneDrive > Silently move Windows known folders to OneDrive*.");
    }
}
