function Push-AuditLogFeedProcessV3 {
    <#
    .SYNOPSIS
        Post-execution for an AuditLogFeedV3 run: processes the windows its tasks stored and runs again the tenants that
        stopped part way.
    .DESCRIPTION
        Each result is a window a feed task stored and left in State Processing: TenantFilter, SearchId, WindowRowKey and
        RecordCount. A task stopped at the platform limit returns nothing, so the windows of the round's CycleId still
        Storing are added. They are queued as one AuditLogTenantProcessV2 item each in a single uncapped run, with one queue
        entry for the run, so nothing is read or written per tenant here. Start-AuditLogFeedV3's sweep queues windows the
        feed run never handed over, through this same function with Parameters.RunName 'AuditLogSweepV3'.

        A tenant whose cursor saved a checkpoint during the round (CheckpointUtc after RoundStartUtc) but was not polled to
        the end (LastPolledUtc before it) is queued again through Start-CIPPAuditLogFeedRun as the next round, for as long
        as rounds keep moving it forward. One that saved nothing waits for the next tick.
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Parameters = $Item.Parameters
    $RunName = $Parameters.RunName ?? 'AuditLogProcessV3'
    $Results = [System.Collections.Generic.List[object]]::new()
    foreach ($Result in @($Item.Results)) { $Results.Add($Result) }
    if ($Parameters.CycleId) {
        try {
            $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
            foreach ($Row in @(Get-CIPPAzDataTableEntity @Ledger -Filter "Type eq 'Feed' and State eq 'Storing' and CycleId eq '$($Parameters.CycleId)'" -Property @('PartitionKey', 'RowKey', 'SearchId', 'CandidateCount'))) {
                $Results.Add([pscustomobject]@{ TenantFilter = [string]$Row.PartitionKey; SearchId = [string]$Row.SearchId; WindowRowKey = [string]$Row.RowKey; RecordCount = [int]$Row.CandidateCount })
            }
        } catch {
            Write-Information "AuditLogFeedProcessV3: could not read the round's stopped windows, the sweep will find them: $($_.Exception.Message)"
        }
    }

    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Windows = foreach ($Result in $Results) {
        if ($Result.TenantFilter -and $Result.SearchId -and $Seen.Add(('{0}|{1}' -f $Result.TenantFilter, $Result.SearchId))) { $Result }
    }
    $Windows = @($Windows)
    if ($Windows.Count -gt 0) {
        $Queue = New-CippQueueEntry -Name 'Audit Logs Process V3' -Reference 'AuditLogsProcessV3' -TotalTasks $Windows.Count
        $Batch = foreach ($Window in $Windows) {
            [pscustomobject]@{
                FunctionName = 'AuditLogTenantProcessV2'
                TenantFilter = [string]$Window.TenantFilter
                SearchId     = [string]$Window.SearchId
                WindowRowKey = [string]$Window.WindowRowKey
                RecordCount  = [int]$Window.RecordCount
                QueueId      = $Queue.RowKey
            }
        }

        Write-Information "AuditLogFeedProcessV3: $($Windows.Count) window(s) queued as $RunName"
        $null = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{
                OrchestratorName = $RunName
                Batch            = @($Batch)
                SkipLog          = $true
                Priority         = 3
            })
    }

    if (-not $Parameters.RoundStartUtc) { return }
    try {
        $RoundStart = ([datetimeoffset]$Parameters.RoundStartUtc).UtcDateTime
        $CursorTable = Get-CippTable -TableName 'AuditLogFeedCursor'
        $Unfinished = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Row in @(Get-CIPPAzDataTableEntity @CursorTable -Property @('PartitionKey', 'RowKey', 'CheckpointUtc', 'LastPolledUtc'))) {
            $Saved = $Row.CheckpointUtc -and ([datetimeoffset]$Row.CheckpointUtc).UtcDateTime -ge $RoundStart
            $Polled = $Row.LastPolledUtc -and ([datetimeoffset]$Row.LastPolledUtc).UtcDateTime -ge $RoundStart
            if ($Saved -and -not $Polled) { $null = $Unfinished.Add([string]$Row.PartitionKey) }
        }
        if ($Unfinished.Count -eq 0) { return }
        $Round = [int]$Parameters.Round + 1
        $Queued = Start-CIPPAuditLogFeedRun -Tenants @(@(Get-CIPPAuditLogTenantScope).Where({ $Unfinished.Contains([string]$_.defaultDomainName) })) -Round $Round
        Write-Information "AuditLogFeedProcessV3: round $Round queued for $Queued tenant(s) still catching up"
    } catch {
        Write-LogMessage -API 'AuditLogFeedV3' -message 'Could not queue the next feed round; the next tick resumes from the saved cursors' -sev Error -LogData (Get-CippException -Exception $_)
    }
}
