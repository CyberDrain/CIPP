function Push-AuditLogFeedFanOutV3 {
    <#
    .SYNOPSIS
        Queues pending AuditLogFeedBlobs rows as one bounded run of blob batch tasks.
    .DESCRIPTION
        Post-execution of the AuditLogFeedListV3 run, and of each AuditLogFeedBlobsV3 run while rows are left. Rows go out
        oldest first in tasks of 64 (tenants together, so a task builds few prefilters), and a run takes at most 80
        tasks: about 5,000 blobs, a few minutes of work, so no run gets near 10 minutes. AuditLogFeedCursorV3 follows
        each run and queues the next until every row has been queued once this cycle.

        Queuing a row counts an attempt (Attempts, LastQueuedUtc) before its task runs, so a blob whose task dies without
        a word is still counted, and a run only takes rows not queued since the cycle began (CycleStartUtc), so a cycle
        cannot loop on rows that keep failing; the next tick tries them again. A row queued 5 times is dropped with a log
        entry, so one bad blob cannot hold a tenant's cursor for good. With nothing to queue, the cursors move now.
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $CycleId = [string]$Item.Parameters.CycleId
    $CycleStart = if ($Item.Parameters.CycleStartUtc) { ([datetimeoffset]$Item.Parameters.CycleStartUtc).UtcDateTime } else { [datetime]::UtcNow }
    $Run = [int]$Item.Parameters.Run
    try {
        $Now = [datetime]::UtcNow
        $BlobTable = Get-CippTable -TableName 'AuditLogFeedBlobs'
        $Rows = @(Get-CIPPAzDataTableEntity @BlobTable -Property @('PartitionKey', 'RowKey', 'TenantId', 'ContentType', 'ContentUri', 'Attempts', 'LastQueuedUtc'))
        $Poisoned = @($Rows.Where({ [int]$_.Attempts -ge 5 }))
        if ($Poisoned.Count -gt 0) {
            foreach ($Tenant in ($Poisoned | Group-Object PartitionKey)) {
                Write-LogMessage -API 'AuditLogFeedV3' -tenant $Tenant.Name -message "$($Tenant.Count) audit log content blob(s) could not be processed in 5 attempts and were skipped; alerts in them are not sent." -sev Error
            }
            Remove-CIPPAzDataTableEntity @BlobTable -Entity @(foreach ($Row in $Poisoned) { @{ PartitionKey = $Row.PartitionKey; RowKey = $Row.RowKey } }) -Force
        }
        $Due = @($Rows.Where({ [int]$_.Attempts -lt 5 -and -not ($_.LastQueuedUtc -and ([datetimeoffset]$_.LastQueuedUtc).UtcDateTime -ge $CycleStart) }) | Sort-Object PartitionKey, RowKey)
        $Take = [Math]::Min($Due.Count, 80 * 64)
        if ($Take -eq 0) {
            Push-AuditLogFeedCursorV3 -Item @{ Parameters = @{ CycleId = $CycleId } }
            return
        }
        $Taken = $Due[0..($Take - 1)]
        $Batch = for ($i = 0; $i -lt $Take; $i += 64) {
            [pscustomobject]@{
                FunctionName = 'AuditLogFeedBlobsV3'
                CycleId      = $CycleId
                Tenants      = @(foreach ($Tenant in ($Taken[$i..([Math]::Min($i + 63, $Take - 1))] | Group-Object PartitionKey)) {
                        [pscustomobject]@{
                            TenantFilter = $Tenant.Name; TenantId = $Tenant.Group[0].TenantId
                            Blobs        = @(foreach ($Row in $Tenant.Group) { [pscustomobject]@{ RowKey = $Row.RowKey; ContentType = $Row.ContentType; contentUri = $Row.ContentUri } })
                        }
                    })
            }
        }
        $null = Add-CIPPAzDataTableEntity @BlobTable -Entity @(foreach ($Row in $Taken) { @{ PartitionKey = $Row.PartitionKey; RowKey = $Row.RowKey; Attempts = [int]$Row.Attempts + 1; LastQueuedUtc = $Now } }) -OperationType UpsertMerge
        $null = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{
                # Later runs of a cycle share the first one's name family, so the timer sees the cycle as still going.
                OrchestratorName = if ($Run -eq 0) { 'AuditLogFeedBlobsV3' } else { "AuditLogFeedBlobsV3-$([guid]::NewGuid())" }
                AllowCollision   = $Run -gt 0
                Batch            = @($Batch)
                SkipLog          = $true
                Priority         = 3
                PostExecution    = @{ FunctionName = 'AuditLogFeedCursorV3'; Parameters = @{ CycleId = $CycleId; CycleStartUtc = $CycleStart.ToString('o'); Run = $Run + 1 } }
            })
        Write-Information "AuditLogFeedFanOutV3: run $Run, $(@($Batch).Count) task(s) for $Take of $($Due.Count) blob(s) due"
    } catch {
        Write-LogMessage -API 'AuditLogFeedV3' -message 'Could not queue the audit log blob batches; the next tick queues them' -sev Error -LogData (Get-CippException -Exception $_)
    }
}
