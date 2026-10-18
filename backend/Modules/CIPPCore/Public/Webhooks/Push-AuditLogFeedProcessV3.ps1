function Push-AuditLogFeedProcessV3 {
    <#
    .SYNOPSIS
        Post-execution for the AuditLogFeedV3 run: processes every window the feed tasks stored, in one run.
    .DESCRIPTION
        Each result is a window a feed task stored and left in State Processing: TenantFilter, SearchId, WindowRowKey and
        RecordCount. They are queued as one AuditLogTenantProcessV2 item each in a single uncapped run, with one queue
        entry for the run, so nothing is read or written per tenant here. The feed timer does not poll while the run is
        going. Start-AuditLogFeedV3's sweep queues windows the feed run never handed over, through this same function
        with Parameters.RunName 'AuditLogSweepV3'.
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $RunName = $Item.Parameters.RunName ?? 'AuditLogProcessV3'
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Windows = foreach ($Result in @($Item.Results)) {
        if ($Result.TenantFilter -and $Result.SearchId -and $Seen.Add(('{0}|{1}' -f $Result.TenantFilter, $Result.SearchId))) { $Result }
    }
    $Windows = @($Windows)
    if ($Windows.Count -eq 0) { return }

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
