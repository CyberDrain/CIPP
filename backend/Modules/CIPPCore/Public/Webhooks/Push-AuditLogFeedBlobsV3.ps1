function Push-AuditLogFeedBlobsV3 {
    <#
    .SYNOPSIS
        Downloads one batch of AuditLogFeedBlobs rows, of any tenants, and sends the alerts their records match.
    .DESCRIPTION
        The batch's blobs download 16 at a time, the next starting as each finishes (Get-CIPPAuditLogContent -Blobs), and
        each goes through the engine as it arrives, exactly as in a tenant's own feed task: records Get-CIPPAuditLogPrefilter rules out are never built, and
        Test-CIPPAuditLogRules matches the rest, claims each alert by record Id, sends it and stores its AuditLogs row.
        A finished blob's row is deleted; a failed one stays, with LastError, for the next tick (its attempt was counted
        when it was queued). A blob evaluated
        again sends nothing twice, since its alerts are already claimed. The task's totals go to AuditLogFeedCycles.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $Now = [datetime]::UtcNow
    $BlobTable = Get-CippTable -TableName 'AuditLogFeedBlobs'
    $Prefilters = @{}
    $Tenants = @{}
    $Blobs = @(foreach ($Tenant in $Item.Tenants) {
            $Tenants[[string]$Tenant.TenantId] = [string]$Tenant.TenantFilter
            $Prefilters[[string]$Tenant.TenantId] = Get-CIPPAuditLogPrefilter -TenantFilter $Tenant.TenantFilter
            foreach ($Blob in $Tenant.Blobs) {
                [pscustomobject]@{ TenantFilter = $Tenant.TenantFilter; TenantId = $Tenant.TenantId; RowKey = $Blob.RowKey; ContentType = $Blob.ContentType; contentUri = $Blob.contentUri }
            }
        })
    if ($Blobs.Count -eq 0) { return }
    $Finished = [System.Collections.Generic.List[object]]::new()
    $Failed = [System.Collections.Generic.List[object]]::new()
    $Totals = @{ Records = 0; Evaluated = 0; Matched = 0 }
    # The engine's directory memo, one per tenant, dropped once the tenant's last blob is in.
    $Memos = @{}

    try {
        $WaitSw = [System.Diagnostics.Stopwatch]::StartNew()
        Get-CIPPAuditLogContent -Blobs $Blobs -Prefilters $Prefilters -MaxConcurrency 16 | ForEach-Object {
            $WaitMs = $WaitSw.Elapsed.TotalMilliseconds
            $Blob = $_.Blob
            $TenantId = [string]$_.TenantId
            $Memo = $Memos[$TenantId]
            if ($_.TenantDone) { $Memos.Remove($TenantId) }
            if ($_.Error) {
                $Failed.Add(@{ PartitionKey = $Blob.TenantFilter; RowKey = $Blob.RowKey; LastError = [string]$_.Error })
                return
            }
            $Totals.Records += $_.RecordCount
            $Records = [System.Collections.Generic.List[object]]::new([object[]]$_.Records)
            $Result = $null
            if ($Records.Count -gt 0) {
                $Totals.Evaluated += $Records.Count
                $Memo ??= [pscustomobject]@{ Tenant = $Blob.TenantFilter; UserLookup = $null; GroupLookup = $null; DeviceLookup = $null; ServicePrincipalLookup = $null }
                if (-not $_.TenantDone) { $Memos[$TenantId] = $Memo }
                $script:AuditRuleSearchLookups = $Memo
                $Result = Test-CIPPAuditLogRules -TenantFilter $Blob.TenantFilter -Rows $Records -CallerSweepsCachePartition
                $script:AuditRuleSearchLookups = $null
                if ($Result.Error) {
                    $Failed.Add(@{ PartitionKey = $Blob.TenantFilter; RowKey = $Blob.RowKey; LastError = [string]$Result.Error })
                    return
                }
                $Totals.Matched += [int]$Result.MatchedLogs
            }
            $Finished.Add(@{ PartitionKey = $Blob.TenantFilter; RowKey = $Blob.RowKey })
            # Per-blob timing for profiling; Debug, so production logging leaves it out.
            Write-Debug ('AuditLogFeedV3 PROFILE {0} {1} records={2} kept={3} matched={4} skipped={5} waitMs={6:F0} parseMs={7:F0} rulesMs={8:F0} alertMs={9:F0}' -f $Blob.TenantFilter, ($Blob.ContentType -replace 'Audit\.', ''), $_.RecordCount, $Records.Count, [int]$Result.MatchedLogs, $_.Skipped, ($WaitMs - $_.ParseMs), $_.ParseMs, ($WaitSw.Elapsed.TotalMilliseconds - $WaitMs - [double]$Result.AlertMs), [double]$Result.AlertMs)
            $WaitSw.Restart()
        }
    } catch {
        Write-Information "AuditLogFeedBlobsV3: the batch stopped: $($_.Exception.Message)"
    }
    $script:AuditRuleSearchLookups = $null

    if ($Finished.Count -gt 0) { Remove-CIPPAzDataTableEntity @BlobTable -Entity $Finished.ToArray() -Force }
    if ($Failed.Count -gt 0) { $null = Add-CIPPAzDataTableEntity @BlobTable -Entity $Failed.ToArray() -OperationType UpsertMerge }
    if ($Item.CycleId) {
        try {
            $CycleTable = Get-CippTable -TableName 'AuditLogFeedCycles'
            $Done = [datetime]::UtcNow
            $null = Add-CIPPAzDataTableEntity @CycleTable -Entity @{
                PartitionKey = 'Feed'; RowKey = '{0}-blobs-{1}' -f $Item.CycleId, ([guid]::NewGuid().ToString('N').Substring(0, 12)); CycleId = [string]$Item.CycleId
                StartedUtc   = $Now; FinishedUtc = $Done; DurationSeconds = [Math]::Round(($Done - $Now).TotalSeconds, 1)
                Tenants      = $Tenants.Count; Feeds = 0; Failed = $Failed.Count; Parked = 0; Blobs = $Blobs.Count
                Records      = [int]$Totals.Records; Evaluated = [int]$Totals.Evaluated; Matched = [int]$Totals.Matched
            } -Force
        } catch {
            Write-Information "AuditLogFeedBlobsV3: could not record the cycle: $($_.Exception.Message)"
        }
    }
}
