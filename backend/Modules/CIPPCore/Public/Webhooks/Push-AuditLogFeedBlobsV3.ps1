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

        Threshold rules (Get-CIPPAuditLogPrefilter Thresholds) are counted, never matched record by record. Each blob's
        counts per identity and 10-minute bucket go to AuditLogFeedThresholds as one row per rule, bucket and blob (a map of
        identity to count), so a blob evaluated twice counts once however many identities it holds, and the identity's counts
        from every task and run are summed from there. A window reaching the rule's Count within its Minutes is alerted by the
        task that moves the identity's '<tenant id>|alert' row (AlertedThroughUtc) forward: an insert, or an ETag-checked
        update, so of two tasks seeing the same burst only one write lands, and the other re-reads and finds it covered.
        An alert carries the count and up to 5 sample records, and quiets the identity for the rule for an hour or the
        rule's Minutes, whichever is longer. The alert carries the identity's latest record of the batch, the one that took
        the count over the threshold; no other records are kept.
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
    $Totals = @{ Records = 0; Evaluated = 0; Matched = 0; Thresholds = 0 }
    # The engine's directory memo, one per tenant, dropped once the tenant's last blob is in.
    $Memos = @{}
    # Threshold count rows by key; '<tenant id>`n<threshold>' -> identities counted; and each identity's latest record (its blob's
    # index and position), the record an alert carries.
    $CountRows = @{}
    $Touched = @{}
    $Latest = @{}

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
                # A threshold rule counts only the log it reads, as a single-record rule matches only its own.
                if ([string]$Prefilters[$TenantId].Thresholds[$Count.Threshold].Rule.LogType -notin '', $Blob.ContentType) { continue }
                $RuleKey = [string]$Prefilters[$TenantId].Thresholds[$Count.Threshold].Rule.RowKey
                $Operations = $Prefilters[$TenantId].Thresholds[$Count.Threshold].Operations
                $Group = "$TenantId`n$($Count.Threshold)"
                if (-not $Touched.ContainsKey($Group)) { $Touched[$Group] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) }
                # Per 10-minute bucket, each identity's count, and each identity's latest record, in one pass over the blob's index.
                $Counted = [System.Collections.Generic.HashSet[string]]::new([string[]]$Operations, [System.StringComparer]::OrdinalIgnoreCase)
                $ByBucket = @{}
                $Values = $Count.Index.Values
                for ($i = 0; $i -lt $Values[0].Length; $i++) {
                    if ($null -eq $Values[0][$i] -or -not $Counted.Contains($Values[0][$i])) { continue }
                    $When = [string]$Values[3][$i]
                    $Bucket = if ($When.Length -gt 15) { $When.Substring(0, 15) } else { $When }
                    $Who = ([string]$Values[2][$i]).ToLowerInvariant()
                    $Counts = $ByBucket[$Bucket]
                    if ($null -eq $Counts) { $Counts = [System.Collections.Generic.Dictionary[string, int]]::new(); $ByBucket[$Bucket] = $Counts }
                    $Seen = 0
                    $null = $Counts.TryGetValue($Who, [ref]$Seen)
                    $Counts[$Who] = $Seen + 1
                    $null = $Touched[$Group].Add($Who)
                    $Last = $Latest["$Group`n$Who"]
                    if ($null -eq $Last -or [string]::CompareOrdinal($When, $Last.Time) -ge 0) { $Latest["$Group`n$Who"] = @{ Index = $Count.Index; At = $i; Time = $When } }
                }
                # One count row per rule, bucket and blob, however many identities the blob holds.
                foreach ($Bucket in $ByBucket.Keys) {
                    $RowKey = '{0}|{1}|{2}' -f $RuleKey, $Bucket, $Blob.RowKey
                    $CountRows["$TenantId`n$RowKey"] = @{ PartitionKey = $TenantId; RowKey = $RowKey; Bucket = $Bucket; Counts = [string]([CIPP.CippJson]::ToJson($ByBucket[$Bucket], 2) ?? (ConvertTo-Json -InputObject $ByBucket[$Bucket] -Compress)) }
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
                $Result = Test-CIPPAuditLogRules -TenantFilter $Blob.TenantFilter -Rows $Records -CallerSweepsCachePartition -LogType $Blob.ContentType
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

    $Alerts = [System.Collections.Generic.List[object]]::new()
    if ($Touched.Count -gt 0) {
        try {
            $ThresholdTable = Get-CippTable -TableName 'AuditLogFeedThresholds'
            Add-CIPPAzDataTableEntity @ThresholdTable -Entity @($CountRows.Values) -Force
            foreach ($Group in $Touched.Keys) {
                $TenantId, $T = $Group -split "`n", 2
                $Threshold = $Prefilters[$TenantId].Thresholds[[int]$T]
                $RuleKey = [string]$Threshold.Rule.RowKey -replace "'", "''"
                $Span = [Math]::Ceiling($Threshold.Minutes / 10)
                $Quiet = [Math]::Max(60, $Threshold.Minutes)
                # Every task's counts for the rule in this tenant, ours included, from a window before the oldest we added.
                $From = $null
                foreach ($Row in $CountRows.Values) {
                    if ($Row.PartitionKey -eq $TenantId -and $Row.RowKey.StartsWith("$($Threshold.Rule.RowKey)|") -and ($null -eq $From -or [string]::CompareOrdinal($Row.Bucket, $From) -lt 0)) { $From = $Row.Bucket }
                }
                $From = [datetime]::ParseExact("$($From)0", 'yyyy-MM-ddTHH:mm', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal').AddMinutes(-10 * $Span).ToString('yyyy-MM-ddTHH:mm').Substring(0, 15)
                # One row per bucket and blob (RowKey '<rule>|<bucket>|<blob>'), each a map of identity to count.
                $Buckets = @{}
                foreach ($Row in @(Get-CIPPAzDataTableEntity @ThresholdTable -Filter "PartitionKey eq '$TenantId' and RowKey ge '$RuleKey|$From' and RowKey lt '$RuleKey|~'")) {
                    # A hashtable: member lookup by name on an object with thousands of members is a scan each time.
                    $Map = try { ConvertFrom-Json -InputObject ([string]$Row.Counts) -AsHashtable } catch { $null }
                    if ($null -eq $Map) { continue }
                    foreach ($Who in $Touched[$Group]) {
                        $Seen = $Map[$Who]
                        if (-not $Seen) { continue }
                        if (-not $Buckets.ContainsKey($Who)) { $Buckets[$Who] = @{} }
                        $Buckets[$Who][$Row.Bucket] = [int]$Buckets[$Who][$Row.Bucket] + [int]$Seen
                    }
                }
                foreach ($Who in $Buckets.Keys) {
                    $Times = @(foreach ($Bucket in $Buckets[$Who].Keys) { [pscustomobject]@{ At = [datetime]::ParseExact("$($Bucket)0", 'yyyy-MM-ddTHH:mm', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal'); Count = $Buckets[$Who][$Bucket] } }) | Sort-Object At
                    # The windows, ending at each bucket, that reach the count; in time order.
                    $Windows = @(foreach ($End in $Times) {
                            $Sum = 0
                            foreach ($Other in $Times) { if ($Other.At -le $End.At -and $Other.At -gt $End.At.AddMinutes(-10 * $Span)) { $Sum += $Other.Count } }
                            if ($Sum -ge $Threshold.Count) { [pscustomobject]@{ End = $End.At.AddMinutes(10); Count = $Sum } }
                        })
                    if ($Windows.Count -eq 0) { continue }
                    $AlertKey = $Who -replace "[\\/#?|\x00-\x1f']", '_'
                    for ($Attempt = 1; $Attempt -le 5; $Attempt++) {
                        $State = Get-CIPPAzDataTableEntity @ThresholdTable -Filter "PartitionKey eq '$TenantId|alert' and RowKey eq '$RuleKey|$AlertKey'"
                        $Through = if ($State.AlertedThroughUtc) { ([datetimeoffset]$State.AlertedThroughUtc).UtcDateTime } else { [datetime]::MinValue }
                        $Fired = [System.Collections.Generic.List[object]]::new()
                        foreach ($Window in $Windows) {
                            if ($Window.End -le $Through) { continue }
                            # Reported at its busiest window before the identity goes quiet.
                            $Burst = $Window
                            foreach ($Later in $Windows) { if ($Later.End -ge $Window.End -and $Later.End -lt $Window.End.AddMinutes($Quiet) -and $Later.Count -gt $Burst.Count) { $Burst = $Later } }
                            $Fired.Add($Burst)
                            $Through = $Window.End.AddMinutes($Quiet)
                        }
                        if ($Fired.Count -eq 0) { break }
                        $Claim = @{ PartitionKey = "$TenantId|alert"; RowKey = "$($Threshold.Rule.RowKey)|$AlertKey"; AlertedThroughUtc = $Through; Count = $Fired[-1].Count }
                        try {
                            if ($State) {
                                $Claim.ETag = $State.ETag
                                Update-CIPPAzDataTableEntity @ThresholdTable -Entity $Claim -OperationType UpdateReplace
                            } else {
                                Add-CIPPAzDataTableEntity @ThresholdTable -Entity $Claim
                            }
                        } catch {
                            # Another task moved the row first: read it again and alert only what it left.
                            continue
                        }
                        foreach ($Burst in $Fired) { $Alerts.Add([pscustomobject]@{ TenantId = $TenantId; Threshold = $Threshold; Who = $Who; Latest = $Latest["$Group`n$Who"]; End = $Burst.End; Count = $Burst.Count }) }
                        break
                    }
                }
            }
        } catch {
            Write-Information "AuditLogFeedBlobsV3: could not count the threshold rules: $($_.Exception.Message)"
        }
    }

    $CIPPURL = $null
    foreach ($Alert in $Alerts) {
        $TenantId, $Threshold, $Who = $Alert.TenantId, $Alert.Threshold, $Alert.Who
        try {
            $TenantFilter = $Tenants[$TenantId]
            # The identity's latest record of the batch, the one that took the count over the threshold.
            $SampleRecords = @([CIPP.CippJson]::ConvertFromIndex($Alert.Latest.Index, [int[]]@($Alert.Latest.At)))
            $Rule = $Threshold.Rule
            if (-not $CIPPURL) {
                $ConfigTable = Get-CippTable -tablename Config
                $CIPPURL = 'https://{0}' -f (Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'").Value
            }
            $Data = [pscustomobject]@{
                Id                    = 'threshold-{0}-{1}-{2:yyyyMMddHHmm}' -f $Rule.RowKey, ($Who -replace '[\\/#?]', '_'), $Alert.End
                CreationTime          = $Alert.End.ToString('yyyy-MM-ddTHH:mm:ss')
                Operation             = "$($Alert.Count) x $($Threshold.Operations -join ' / ')"
                UserId                = $Who
                Workload              = $SampleRecords[0].Workload
                RecordType            = $SampleRecords[0].RecordType
                ClientIP              = $SampleRecords[0].ClientIP
                ObjectId              = @($SampleRecords.ObjectId) -join ', '
                CIPPAction            = $Rule.Actions
                CIPPBecActions        = $Rule.BecActions
                CIPPClause            = '{0} of {1} by {2} within {3} minutes (threshold {4})' -f $Alert.Count, ($Threshold.Operations -join ', '), $Who, $Threshold.Minutes, $Threshold.Count
                CIPPAlertComment      = $Rule.AlertComment
                CIPPRuleKey           = $Rule.RowKey
                CIPPCustomSubject     = $Rule.CustomSubject
                CIPPPsaTicketPriority = $Rule.PsaTicketPriority
                CIPPThresholdCount    = $Alert.Count
                AuditRecord           = [string]([CIPP.CippJson]::ToJson($SampleRecords, 10) ?? (ConvertTo-Json -InputObject $SampleRecords -Depth 10 -Compress))
            }
            $Rows = [System.Collections.Generic.List[object]]::new()
            Invoke-CippWebhookProcessing -Data $Data -CIPPURL $CIPPURL -TenantFilter $TenantFilter -AlertComment $Rule.AlertComment -PendingAuditLogWrites $Rows
            if ($Rows.Count -gt 0) {
                $AuditLogTable = Get-CIPPTable -TableName 'AuditLogs'
                Add-CIPPAzDataTableEntity @AuditLogTable -Entity $Rows.ToArray() -Force
            }
            $Totals.Matched++
            $Totals.Thresholds++
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
                Records      = [int]$Totals.Records; Evaluated = [int]$Totals.Evaluated; Matched = [int]$Totals.Matched; Thresholds = [int]$Totals.Thresholds
            } -Force
        } catch {
            Write-Information "AuditLogFeedBlobsV3: could not record the cycle: $($_.Exception.Message)"
        }
    }
}
