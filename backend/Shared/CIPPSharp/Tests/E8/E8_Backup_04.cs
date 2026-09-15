namespace CIPP.Tests
{
    /// <summary>
    /// E8 ML2 (Regular Backups) — Microsoft 365 data is backed up by a tested process (ISM-1547).
    /// Port of Invoke-CippTestE8_Backup_04. Manual/informational task; always Informational.
    /// </summary>
    public sealed class E8_Backup_04 : ICippTest
    {
        public string Id => "E8_Backup_04";

        public CippTestResult Evaluate(TenantData data, ILogSink log)
            => new CippTestResult(TestStatus.Informational,
                "This is a task performed manually. Confirm a third-party (or Microsoft 365 Backup) solution is in place for mailboxes, OneDrive, SharePoint, and Teams data, and that restore tests are performed at least quarterly with documented results. Microsoft retention is **not** a backup — it does not protect against admin deletion or compliance policy changes.");
    }
}
