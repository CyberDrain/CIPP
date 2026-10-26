function Start-AuditLogPlannerV2 {
    <#
    .SYNOPSIS
        Single timer entrypoint for the V2 audit-log pipeline. Runs every 15 minutes and drives both
        stages: plan + create searches, then download + process.
    .DESCRIPTION
        Replaces the separate Start-AuditLogSearchCreationV2 and Start-AuditLogIngestionV2 timers with
        one planner so the whole pipeline ticks together:

          Stage 1 (create) - Start-AuditLogSearchCreationV2: seeds owed 35-min windows (20-min settle,
            ends on the :10/:40 grid so a fresh window is creatable exactly at :00/:30 with no tick
            delay) plus 12-hour reconciliation windows, then creates the oldest <= 6 due windows per
            tenant with auto-retry disabled and manual 429 back-off.

          Stage 2 (ingest) - Start-AuditLogIngestionV2: downloads searches created in PRIOR ticks that
            are now ready, processes them, and re-processes any tenant with leftover cache rows.

        The two stages operate on different windows (stage 1 queues new searches; stage 2 consumes
        searches from earlier ticks once Graph has finished them), so running them in one tick simply
        pipelines the work.

        Does nothing while the Audit Log Feed feature is enabled: Start-AuditLogFeedV3 then collects the logs and
        processes the searches already created.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param()
    # The host scheduler fires every CIPPTimers.json entry regardless of feature flags, so the planner gates itself.
    $FeedFlag = $(try { Get-CIPPFeatureFlag -Id 'AuditLogFeed' } catch { $null })
    if ($FeedFlag.Enabled -eq $true) {
        Write-Information 'AuditLogV2: skipped, the Audit Log Feed feature collects audit logs instead of Graph searches'
        return
    }
    try {
        Start-AuditLogSearchCreationV2
    } catch {
        Write-LogMessage -API 'AuditLogV2' -message 'Planner: search creation stage failed' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information ('AuditLogV2 planner (create) error: {0}' -f $_.Exception.Message)
    }
    try {
        Start-AuditLogIngestionV2
    } catch {
        Write-LogMessage -API 'AuditLogV2' -message 'Planner: ingestion stage failed' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information ('AuditLogV2 planner (ingest) error: {0}' -f $_.Exception.Message)
    }
}
