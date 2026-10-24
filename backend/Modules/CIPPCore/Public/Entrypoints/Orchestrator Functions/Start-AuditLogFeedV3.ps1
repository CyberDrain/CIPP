function Start-AuditLogFeedV3 {
    <#
    .SYNOPSIS
        Timer entrypoint for audit log alerting: the Management Activity API feed, plus Graph audit searches already
        created.
    .DESCRIPTION
        Each tick runs three independent stages:
          1. Sweep: feed windows still Storing, Downloaded or Processing after the run that wrote them has gone are queued
             again through AuditLogFeedProcessV3, as an AuditLogSweepV3 run: older than 5 minutes with no feed,
             processing or sweep run active, or Processing for more than 2 hours whatever is running. It runs before
             the feed stage, which would otherwise always look active.
          2. Feed: skipped while an AuditLogProcessV3 run is still going, so polling never competes with processing for
             background slots; the cursors carry the skipped range to the next tick. Otherwise Start-CIPPAuditLogFeedRun
             queues one AuditLogFeedV3 task per in-scope tenant with a content type due; its post-execution processes
             what the tasks stored and runs the tenants that checkpointed but did not finish again.
          3. Graph searches: Start-AuditLogIngestionV2 downloads and processes searches that already exist, which are
             manual searches and scheduled windows created before the feed. No scheduled searches are created.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $Now = [datetime]::UtcNow

    $Bridge = 'Craft.Services.OrchestratorBridge' -as [type]
    try {
        $RunsActive = $Bridge -and @('AuditLogFeedV3', 'AuditLogProcessV3', 'AuditLogSweepV3').Where({ [Craft.Services.OrchestratorBridge]::IsRunActive($_) }, 'First').Count -gt 0
        $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
        $Missed = foreach ($Row in @(Get-CIPPAzDataTableEntity @Ledger -Filter "Type eq 'Feed' and (State eq 'Storing' or State eq 'Downloaded' or State eq 'Processing')" -Property @('PartitionKey', 'RowKey', 'State', 'SearchId', 'CandidateCount', 'Timestamp'))) {
            $Age = $Now - $Row.Timestamp.UtcDateTime
            if ((-not $RunsActive -and $Age.TotalMinutes -gt 5) -or ($Row.State -eq 'Processing' -and $Age.TotalHours -gt 2)) {
                [pscustomobject]@{ TenantFilter = [string]$Row.PartitionKey; SearchId = [string]$Row.SearchId; WindowRowKey = [string]$Row.RowKey; RecordCount = [int]$Row.CandidateCount }
            }
        }
        $Missed = @($Missed)
        if ($Missed.Count -gt 0 -and $PSCmdlet.ShouldProcess('Start-AuditLogFeedV3', "Process $($Missed.Count) feed window(s) whose run is gone")) {
            Write-Information "AuditLogFeedV3: $($Missed.Count) feed window(s) whose run is gone"
            Push-AuditLogFeedProcessV3 -Item ([pscustomobject]@{ Results = $Missed; Parameters = @{ RunName = 'AuditLogSweepV3' } })
        }
    } catch {
        Write-LogMessage -API 'AuditLogFeedV3' -message 'Audit log feed sweep failed' -sev Error -LogData (Get-CippException -Exception $_)
    }

    $ProcessingActive = $Bridge -and [Craft.Services.OrchestratorBridge]::IsRunActive('AuditLogProcessV3')
    if ($ProcessingActive) {
        Write-Information 'AuditLogFeedV3: feed skipped, audit log processing is still running'
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
