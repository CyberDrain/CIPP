namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML1 (Regular Backups) — SharePoint Online versioning and recycle bin retention is
    /// configured. Port of Invoke-CippTestE8_Backup_02. Manual/informational task; always Informational.
    /// </summary>
    public sealed class E8_Backup_02 : ICippTest
    {
        public string Id => "E8_Backup_02";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm SharePoint Online sites have versioning enabled (default minimum 100 versions) and the second-stage recycle bin retention is at least 93 days. Site-level versioning is configured per library and is not exposed centrally; review via SharePoint admin centre or PnP PowerShell.");
    }
}
