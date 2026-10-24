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

        Threshold rules (Get-CIPPAuditLogPrefilter Thresholds) are counted, never matched record by record: the counts per
        identity and 10-minute bucket that Get-CIPPAuditLogContent takes from each blob's index are summed over the task,
        and an identity whose records reach a rule's Count within its Minutes gets one alert, carrying the count and up to
        5 sample records, claimed as 'threshold-<rule>-<identity>-<hour>' so the same burst alerts once however its blobs
        were split.
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
    # '<tenant id>`n<threshold>`n<identity>' -> 10-minute bucket -> records; and the first blob index holding each, for samples.
    $Tallies = @{}
    $SampleIndex = @{}

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
            foreach ($Count in @($_.Counts)) {
                if ($null -eq $Count) { continue }
                foreach ($Pair in $Count.Counts.GetEnumerator()) {
                    $Who, $Bucket = $Pair.Key -split '\|', 2
                    $Key = "$TenantId`n$($Count.Threshold)`n$Who"
                    if (-not $Tallies.ContainsKey($Key)) { $Tallies[$Key] = @{}; $SampleIndex[$Key] = @{ Index = $Count.Index; Key = $Pair.Key } }
                    $Tallies[$Key][$Bucket] = [int]$Tallies[$Key][$Bucket] + $Pair.Value
                }
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

    $CIPPURL = $null
    foreach ($Key in $Tallies.Keys) {
        $TenantId, $T, $Who = $Key -split "`n", 3
        $Threshold = $Prefilters[$TenantId].Thresholds[[int]$T]
        # The busiest run of buckets that fits in the rule's window.
        $Span = [Math]::Ceiling($Threshold.Minutes / 10)
        $Times = @(foreach ($Bucket in $Tallies[$Key].Keys) { [pscustomobject]@{ At = [datetime]::ParseExact("$($Bucket)0", 'yyyy-MM-ddTHH:mm', [cultureinfo]::InvariantCulture); Count = $Tallies[$Key][$Bucket] } })
        $Best = $null
        foreach ($End in $Times) {
            $Sum = 0
            foreach ($Other in $Times) { if ($Other.At -le $End.At -and $Other.At -gt $End.At.AddMinutes(-10 * $Span)) { $Sum += $Other.Count } }
            if ($Sum -ge $Threshold.Count -and ($null -eq $Best -or $Sum -gt $Best.Count)) { $Best = [pscustomobject]@{ At = $End.At; Count = $Sum } }
        }
        if (-not $Best) { continue }
        try {
            $TenantFilter = $Tenants[$TenantId]
            $Sample = $SampleIndex[$Key]
            $SampleRecords = @([CIPP.CippJson]::ConvertFromIndex($Sample.Index, $Sample.Index.IndicesWhere(0, $Threshold.Operations, [int[]]@(2, 3), [int[]]@(-1, 15), $Sample.Key, 5)))
            $Rule = $Threshold.Rule
            if (-not $CIPPURL) {
                $ConfigTable = Get-CippTable -tablename Config
                $CIPPURL = 'https://{0}' -f (Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'").Value
            }
            $Data = [pscustomobject]@{
                Id                    = 'threshold-{0}-{1}-{2:yyyyMMddHH}' -f $Rule.RowKey, ($Who -replace '[\\/#?]', '_'), $Best.At
                CreationTime          = $Best.At.AddMinutes(10).ToString('yyyy-MM-ddTHH:mm:ss')
                Operation             = "$($Best.Count) x $($Threshold.Operations -join ' / ')"
                UserId                = $Who
                Workload              = $SampleRecords[0].Workload
                RecordType            = $SampleRecords[0].RecordType
                ClientIP              = $SampleRecords[0].ClientIP
                ObjectId              = @($SampleRecords.ObjectId) -join ', '
                CIPPAction            = $Rule.Actions
                CIPPBecActions        = $Rule.BecActions
                CIPPClause            = '{0} of {1} by {2} within {3} minutes (threshold {4})' -f $Best.Count, ($Threshold.Operations -join ', '), $Who, $Threshold.Minutes, $Threshold.Count
                CIPPAlertComment      = $Rule.AlertComment
                CIPPCustomSubject     = $Rule.CustomSubject
                CIPPPsaTicketPriority = $Rule.PsaTicketPriority
                CIPPThresholdCount    = $Best.Count
                AuditRecord           = [string]([CIPP.CippJson]::ToJson($SampleRecords, 10) ?? (ConvertTo-Json -InputObject $SampleRecords -Depth 10 -Compress))
            }
            $Rows = [System.Collections.Generic.List[object]]::new()
            Invoke-CippWebhookProcessing -Data $Data -CIPPURL $CIPPURL -TenantFilter $TenantFilter -AlertComment $Rule.AlertComment -PendingAuditLogWrites $Rows
            if ($Rows.Count -gt 0) {
                $AuditLogTable = Get-CIPPTable -TableName 'AuditLogs'
                Add-CIPPAzDataTableEntity @AuditLogTable -Entity $Rows.ToArray() -Force
            }
            $Totals.Matched++
        } catch {
            Write-Information "AuditLogFeedBlobsV3: could not send the threshold alert for $Who in $($Tenants[$TenantId]): $($_.Exception.Message)"
        }
    }

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
