function Push-AuditLogFeedRoundV3 {
    <#
    .SYNOPSIS
        Post-execution for an AuditLogFeedV3 run: runs again the tenants whose feed task stopped part way.
    .DESCRIPTION
        A tenant whose cursor saved a checkpoint during the round (CheckpointUtc after RoundStartUtc) but was not read to
        the end (LastPolledUtc before it) is queued again through Start-CIPPAuditLogFeedRun as the next round, for as
        long as rounds keep moving it forward. One that saved nothing waits for the next tick.
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $Parameters = $Item.Parameters
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
        Write-Information "AuditLogFeedRoundV3: round $Round queued for $Queued tenant(s) still catching up"
    } catch {
        Write-LogMessage -API 'AuditLogFeedV3' -message 'Could not queue the next feed round; the next tick resumes from the saved cursors' -sev Error -LogData (Get-CippException -Exception $_)
    }
}
