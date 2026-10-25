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

        Threshold rules (Get-CIPPAuditLogPrefilter Thresholds) are counted, never matched record by record. The counts per
        identity and 10-minute bucket that Get-CIPPAuditLogContent takes from each blob's index are stored in
        AuditLogFeedThresholds, one row per blob, so a blob evaluated twice counts once, and the identity's counts from
        every task and run are summed from there. A window reaching the rule's Count within its Minutes is alerted by the
        task that moves the identity's '<tenant id>|alert' row (AlertedThroughUtc) forward: an insert, or an ETag-checked
        update, so of two tasks seeing the same burst only one write lands, and the other re-reads and finds it covered.
        An alert carries the count and up to 5 sample records, and quiets the identity for the rule for an hour or the
        rule's Minutes, whichever is longer. Each count row also keeps up to 60 of its records in compact form (time,
        operation, item, IP address, device); when an alert is saved, the records in its window, up to 500, go to
        AuditLogRelatedRecords beside it, out of the notification, and are removed with the other logs under the log
        retention setting.
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
    # Threshold count rows by key; '<tenant id>`n<threshold>' -> identities counted; and a blob index holding each, for samples.
    $CountRows = @{}
    $Touched = @{}
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
                $RuleKey = [string]$Prefilters[$TenantId].Thresholds[$Count.Threshold].Rule.RowKey
                $Operations = $Prefilters[$TenantId].Thresholds[$Count.Threshold].Operations
                $Group = "$TenantId`n$($Count.Threshold)"
                if (-not $Touched.ContainsKey($Group)) { $Touched[$Group] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase) }
                # Each identity's first 60 records, in one pass: a password spray has a different username on every record.
                $Counted = [System.Collections.Generic.HashSet[string]]::new([string[]]$Operations, [System.StringComparer]::OrdinalIgnoreCase)
                $ByKey = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[int]]]::new([System.StringComparer]::OrdinalIgnoreCase)
                $Values = $Count.Index.Values
                for ($i = 0; $i -lt $Values[0].Length; $i++) {
                    if ($null -eq $Values[0][$i] -or -not $Counted.Contains($Values[0][$i])) { continue }
                    $When = [string]$Values[3][$i]
                    $Key = '{0}|{1}' -f [string]$Values[2][$i], $(if ($When.Length -gt 15) { $When.Substring(0, 15) } else { $When })
                    $List = $null
                    if (-not $ByKey.TryGetValue($Key, [ref]$List)) { $List = [System.Collections.Generic.List[int]]::new(); $ByKey[$Key] = $List }
                    if ($List.Count -lt 60) { $List.Add($i) }
                }
                # ponytail: only the 1,000 busiest identities of a blob are counted; past that a blob is a spray of names that each
                # appear a few times, which no per-identity threshold reaches. Count the spray itself if that needs alerting.
                $Pairs = @($Count.Counts.GetEnumerator())
                if ($Pairs.Count -gt 1000) { $Pairs = @($Pairs | Sort-Object Value -Descending)[0..999] }
                foreach ($Pair in $Pairs) {
                    $Who, $Bucket = $Pair.Key -split '\|', 2
                    $Who = $Who.ToLowerInvariant()
                    if ($Touched[$Group].Add($Who)) { $SampleIndex["$Group`n$Who"] = @{ Index = $Count.Index; Key = $Pair.Key } }
                    $RowKey = '{0}|{1}|{2}|{3}' -f $RuleKey, ($Who -replace '[\\/#?|\x00-\x1f]', '_'), $Bucket, $Blob.RowKey
                    # The records behind the count, compact and at most 60 a row, so an alert can list what one identity did.
                    $Kept = [System.Collections.Generic.List[object]]::new()
                    if ($CountRows["$TenantId`n$RowKey"].Records) { $Kept.AddRange([object[]]@([CIPP.CippJson]::ConvertFromJson($CountRows["$TenantId`n$RowKey"].Records))) }
                    foreach ($Record in @([CIPP.CippJson]::ConvertFromIndex($Count.Index, $ByKey[$Pair.Key].ToArray()))) {
                        $Item = [string]($Record.ObjectId ?? $Record.SourceFileName)
                        $Device = [string]($Record.UserAgent ?? $Record.ClientInfoString ?? $Record.ApplicationDisplayName)
                        $Kept.Add([ordered]@{
                                Time      = $Record.CreationTime
                                Operation = $Record.Operation
                                Item      = if ($Item.Length -gt 200) { $Item.Substring(0, 200) } else { $Item }
                                IP        = $Record.ClientIP ?? $Record.ClientIPAddress
                                Device    = if ($Device.Length -gt 120) { $Device.Substring(0, 120) } else { $Device }
                            })
                    }
                    $CountRows["$TenantId`n$RowKey"] = @{
                        PartitionKey = $TenantId; RowKey = $RowKey; Who = $Who; Bucket = $Bucket; Count = [int]$Pair.Value + [int]$CountRows["$TenantId`n$RowKey"].Count
                        Records      = [string]([CIPP.CippJson]::ToJson($Kept.ToArray(), 4) ?? (ConvertTo-Json -InputObject $Kept.ToArray() -Depth 4 -Compress))
                    }
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
                $Buckets = @{}
                foreach ($Row in @(Get-CIPPAzDataTableEntity @ThresholdTable -Filter "PartitionKey eq '$TenantId' and RowKey ge '$RuleKey|' and RowKey lt '$RuleKey}' and Bucket ge '$From'" -Property @('RowKey', 'Who', 'Bucket', 'Count'))) {
                    if (-not $Touched[$Group].Contains([string]$Row.Who)) { continue }
                    if (-not $Buckets.ContainsKey($Row.Who)) { $Buckets[$Row.Who] = @{} }
                    $Buckets[$Row.Who][$Row.Bucket] = [int]$Buckets[$Row.Who][$Row.Bucket] + [int]$Row.Count
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
                        # The records kept with the counts, read only for an identity that alerts.
                        $WhoKey = ($Who -replace '[\\/#?|\x00-\x1f]', '_') -replace "'", "''"
                        $Related = @(foreach ($Row in @(Get-CIPPAzDataTableEntity @ThresholdTable -Filter "PartitionKey eq '$TenantId' and RowKey ge '$RuleKey|$WhoKey|' and RowKey lt '$RuleKey|$WhoKey}' and Bucket ge '$From'")) { if ($Row.Records) { [string]$Row.Records } })
                        foreach ($Burst in $Fired) { $Alerts.Add([pscustomobject]@{ TenantId = $TenantId; Threshold = $Threshold; Who = $Who; Sample = $SampleIndex["$Group`n$Who"]; End = $Burst.End; Count = $Burst.Count; Related = $Related }) }
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
            $Sample = $Alert.Sample
            $SampleRecords = @([CIPP.CippJson]::ConvertFromIndex($Sample.Index, $Sample.Index.IndicesWhere(0, $Threshold.Operations, [int[]]@(2, 3), [int[]]@(-1, 15), $Sample.Key, 5)))
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
                # Every record of the burst kept while counting, up to 500, beside the saved alert and under log retention.
                $From = $Alert.End.AddMinutes(-10 * [Math]::Ceiling($Threshold.Minutes / 10)).ToString('yyyy-MM-ddTHH:mm:ss')
                $To = $Alert.End.ToString('yyyy-MM-ddTHH:mm:ss')
                $InWindow = [System.Collections.Generic.List[object]]::new()
                foreach ($Json in @($Alert.Related)) {
                    foreach ($Record in @([CIPP.CippJson]::ConvertFromJson($Json))) {
                        # CippJson reads the ISO time back as a DateTime; compare and keep it as the audit log writes it.
                        if ($Record.Time -is [datetime]) { $Record.Time = $Record.Time.ToString('yyyy-MM-ddTHH:mm:ss') }
                        if ([string]::CompareOrdinal([string]$Record.Time, $From) -ge 0 -and [string]::CompareOrdinal([string]$Record.Time, $To) -lt 0) { $InWindow.Add($Record) }
                    }
                }
                $InWindow.Sort([System.Comparison[object]] { param($A, $B) [string]::CompareOrdinal([string]$A.Time, [string]$B.Time) })
                $Kept = @(if ($InWindow.Count -gt 500) { $InWindow.GetRange(0, 500) } else { $InWindow })
                if ($Kept.Count -gt 0) {
                    $RelatedTable = Get-CIPPTable -TableName 'AuditLogRelatedRecords'
                    Add-CIPPAzDataTableEntity @RelatedTable -Force -Entity @{
                        PartitionKey = $TenantFilter; RowKey = $Data.Id; Total = [int]$Alert.Count
                        Records      = [string]([CIPP.CippJson]::ToJson($Kept, 4) ?? (ConvertTo-Json -InputObject $Kept -Depth 4 -Compress))
                    }
                }
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
