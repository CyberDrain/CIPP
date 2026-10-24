function Start-AuditLogFeedV3 {
    <#
    .SYNOPSIS
        Timer entrypoint for audit log alerting: the Management Activity API feed, plus Graph audit searches already
        created.
    .DESCRIPTION
        Each tick runs two independent stages:
          1. Feed: while a feed round is still going (AuditLogFeedV3 or a later AuditLogFeedV3-<guid> round) the tick
             leaves it be; the cursors carry the range to the round. Otherwise Start-CIPPAuditLogFeedRun queues one
             AuditLogFeedV3 task per in-scope tenant with a content type due. Each task reads its feed and sends its alerts
             itself, and the run's post-execution runs again the tenants that checkpointed but did not finish.
          2. Graph searches: Start-AuditLogIngestionV2 downloads and processes searches that already exist, which are
             manual searches and scheduled windows created before the feed. No scheduled searches are created.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $Bridge = 'Craft.Services.OrchestratorBridge' -as [type]
    if ($Bridge -and [Craft.Services.OrchestratorBridge]::IsRunActive('AuditLogFeedV3')) {
        Write-Information 'AuditLogFeedV3: a feed round is still running'
    } else {
        try {
            if ($PSCmdlet.ShouldProcess('Start-AuditLogFeedV3', 'Poll the audit log feed')) {
                $Queued = Start-CIPPAuditLogFeedRun -Tenants @(Get-CIPPAuditLogTenantScope)
                Write-Information "AuditLogFeedV3: $Queued tenant task(s) queued"
            }
        } catch {
            Write-LogMessage -API 'AuditLogFeedV3' -message 'Audit log feed stage failed' -sev Error -LogData (Get-CippException -Exception $_)
        }
    }

    try {
        Start-AuditLogIngestionV2
    } catch {
        Write-LogMessage -API 'AuditLogFeedV3' -message 'Audit log search ingestion failed' -sev Error -LogData (Get-CippException -Exception $_)
    }
}
