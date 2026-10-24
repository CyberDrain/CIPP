function Push-AuditLogFeedV3 {
    <#
    .SYNOPSIS
        Reads a tenant's Management Activity API feed and sends the alerts its rules match, checkpointing as it goes.
    .DESCRIPTION
        Per content type, lists the blobs published since the AuditLogFeedCursor row (the last hour for a new cursor,
        never more than 7 days back) in 6-hour ranges: the API takes up to 24 hours a call but is slow and unreliable at
        that size, and a shorter range lets the cursor move on sooner. Get-CIPPAuditLogContent
        downloads them a few at a time and hands each over as it arrives; records Get-CIPPAuditLogPrefilter rules out
        are dropped, and the rest go through the whole engine in place: Test-CIPPAuditLogRules matches them, claims
        each alert by record Id, sends it and stores its AuditLogs row. Nothing is staged and no processing run follows.

        Whenever a finished blob moves it, the cursor is saved (LastEndUtc, CheckpointUtc) just before the oldest listed
        blob not yet finished, so a task stopped at the platform limit resumes there, and AuditLogFeedRoundV3 runs the tenant
        again while it progresses. A blob evaluated again after a stop sends nothing twice: its alerts are already
        claimed. A failure keeps the cursor at that point and the rest is read again next cycle.

        AF20022 (no subscription) and AF20023 (subscription disabled) start one. A tenant with no audit log to read -
        the start call reports the tenant missing (unified audit log ingestion off), or the token fails with
        AADSTS500014 (the Office 365 Management APIs service principal is disabled, as in unlicensed tenants) - is
        parked for a day with the reason on the cursor row. Other failures back off with Get-CippAuditLogNextAttempt.
        The task's totals and timing are written to AuditLogFeedCycles under the item's CycleId, and each cursor keeps
        its last read's counts.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $Now = [datetime]::UtcNow
    # Blobs published in the last few minutes can still be missing from a listing.
    $End = $Now.AddMinutes(-5)
    $Floor = $Now.AddDays(-7).AddMinutes(10)
    $CursorTable = Get-CippTable -TableName 'AuditLogFeedCursor'

    $Queries = foreach ($Tenant in $Item.Tenants) {
        foreach ($ContentType in $Tenant.ContentTypes) {
            $LastEnd = $Tenant.Cursors.$ContentType.LastEndUtc
            $Start = if ($LastEnd) { ([datetimeoffset]$LastEnd).UtcDateTime } else { $End.AddHours(-1) }
            if ($Start -lt $Floor) {
                Write-LogMessage -API 'AuditLogFeedV3' -tenant $Tenant.TenantFilter -message "The $ContentType feed was last read at $($Start.ToString('o')). Content older than 7 days is no longer available and was skipped." -sev Warning
                $Start = $Floor
            }
            # A longer backlog is listed in consecutive 6-hour ranges.
            for ($RangeStart = $Start; $RangeStart -lt $End; $RangeStart = $RangeEnd) {
                $RangeEnd = if ($RangeStart.AddHours(6) -lt $End) { $RangeStart.AddHours(6) } else { $End }
                @{ TenantFilter = $Tenant.TenantFilter; TenantId = $Tenant.TenantId; ContentType = $ContentType; StartTime = $RangeStart; EndTime = $RangeEnd }
            }
        }
    }
    $Queries = @($Queries)
    if ($Queries.Count -eq 0) { return }

    $CursorUpdates = [System.Collections.Generic.List[object]]::new()
    $Failures = [System.Collections.Generic.List[object]]::new()
    # One entry per cursor, keyed '<tenant id>|<content type>', so the cursor decision never depends on arrival order.
    # Each listing range keeps the blobs listed and not yet finished; blobs that finish before their listing arrives
    # wait in Done.
    $Progress = @{}
    foreach ($Query in $Queries) {
        $Key = '{0}|{1}' -f $Query.TenantId, $Query.ContentType
        if (-not $Progress[$Key]) {
            $Progress[$Key] = @{
                Query = @{ TenantFilter = $Query.TenantFilter; TenantId = $Query.TenantId; ContentType = $Query.ContentType; StartTime = $Query.StartTime; EndTime = $Query.EndTime }
                Ranges = [System.Collections.Generic.List[object]]::new(); Saved = $Query.StartTime
                Blobs = 0; Records = 0; Matched = 0; Failure = $null; Subscribed = $false
            }
        }
        $Entry = $Progress[$Key]
        $Entry.Query.EndTime = $Query.EndTime
        $Entry.Ranges.Add(@{ Start = $Query.StartTime; End = $Query.EndTime; Listed = $false; ListedThrough = $Query.StartTime; Pending = [System.Collections.Generic.Dictionary[string, string]]::new(); Order = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal); Done = [System.Collections.Generic.HashSet[string]]::new() })
    }
    # Where the cursor can safely stand: just before the oldest listed blob not yet finished, and in a range whose
    # listing is still paging, no later than just before the newest blob listed so far. Listings come back oldest
    # first, so everything before that point is in. Pending maps a blob id to its key in Order, '<created ticks>|<id>',
    # so the oldest is Order.Min rather than a scan of every pending blob.
    $Frontier = {
        param($Entry)
        foreach ($Range in $Entry.Ranges) {
            $Point = $null
            if ($Range.Order.Count -gt 0) {
                $Point = [datetime]::new([long]$Range.Order.Min.Substring(0, 19), [System.DateTimeKind]::Utc).AddSeconds(-1)
            }
            if (-not $Range.Listed) {
                $Listed = $Range.ListedThrough.AddSeconds(-1)
                if ($null -eq $Point -or $Listed -lt $Point) { $Point = $Listed }
            }
            if ($null -ne $Point) { return $(if ($Point -gt $Range.Start) { $Point } else { $Range.Start }) }
        }
        $Entry.Ranges[-1].End
    }
    $BlobDone = {
        param($Entry, $Blob)
        $Id = [string]$Blob.contentId
        $Range = $Entry.Ranges.Where({ $_.Pending.ContainsKey($Id) }, 'First')[0]
        if ($Range) {
            $null = $Range.Order.Remove($Range.Pending[$Id])
            $null = $Range.Pending.Remove($Id)
        } else { foreach ($Unlisted in $Entry.Ranges) { $null = $Unlisted.Done.Add($Id) } }
        $Checkpoint = & $Frontier $Entry
        if ($Checkpoint -le $Entry.Saved) { return }
        try {
            $null = Add-CIPPAzDataTableEntity @CursorTable -Entity @{ PartitionKey = $Entry.Query.TenantFilter; RowKey = $Entry.Query.ContentType; LastEndUtc = $Checkpoint; CheckpointUtc = [datetime]::UtcNow } -OperationType UpsertMerge
            $Entry.Saved = $Checkpoint
        } catch {
            Write-Information "AuditLogFeedV3: could not save the $($Entry.Query.ContentType) checkpoint for $($Entry.Query.TenantFilter): $($_.Exception.Message)"
        }
    }
    $Totals = @{}
    $Prefilters = @{}
    foreach ($Tenant in $Item.Tenants) {
        $Totals[[string]$Tenant.TenantId] = @{ TenantFilter = $Tenant.TenantFilter; Records = 0; Evaluated = 0; Matched = 0 }
        if ($Tenant.ContentTypes) { $Prefilters[[string]$Tenant.TenantId] = Get-CIPPAuditLogPrefilter -TenantFilter $Tenant.TenantFilter }
    }
    # The engine's directory memo, one per tenant, dropped once the tenant's last blob is in.
    $Memos = @{}

    try {
        # A few downloads run ahead of the blob being evaluated, so evaluation is not waiting on Microsoft's latency.
        Get-CIPPAuditLogContent -Queries $Queries -Prefilters $Prefilters -MaxConcurrency 4 | ForEach-Object {
            $TenantId = [string]$_.TenantId
            $Memo = $Memos[$TenantId]
            if ($_.TenantDone) { $Memos.Remove($TenantId) }

            if ($_.Kind -eq 'Listing') {
                $Entry = $Progress['{0}|{1}' -f $TenantId, $_.ContentType]
                if ($Entry.Subscribed) { return }
                if ($_.ErrorCode -in @('AF20022', 'AF20023')) {
                    try {
                        $null = New-GraphPOSTRequest -type POST -uri ('https://manage.office.com/api/v1.0/{0}/activity/feed/subscriptions/start?contentType={1}&PublisherIdentifier={2}' -f $TenantId, $_.ContentType, $env:TenantID) -body '{}' -scope 'https://manage.office.com/.default' -tenantid $TenantId -NoAuthCheck $true
                        Write-LogMessage -API 'AuditLogFeedV3' -tenant $_.TenantFilter -message "Started the $($_.ContentType) audit log subscription. Microsoft can take up to 12 hours to publish the first content." -sev Info
                        $Entry.Subscribed = $true
                        $CursorUpdates.Add(@{ PartitionKey = $_.TenantFilter; RowKey = $_.ContentType; LastEndUtc = $_.EndTime; LastPolledUtc = $Now; SubscriptionStartedUtc = $Now; Attempts = 0; NextAttemptUtc = $Now; LastErrorCode = ''; LastError = '' })
                    } catch {
                        $Entry.Failure ??= if ($_.Exception.Message -match 'Tenant .+ does not exist') {
                            @{ Code = 'AuditLogDisabled'; Message = 'Unified audit logging is turned off for this tenant. Turn it on with the AuditLog standard; Microsoft can take up to 12 hours to publish content after the subscription starts.' }
                        } else {
                            @{ Code = 'SubscriptionStart'; Message = $_.Exception.Message }
                        }
                    }
                } elseif ($_.ErrorCode -eq 'Token' -and $_.Error -match 'AADSTS500014') {
                    $Entry.Failure ??= @{ Code = 'NoAuditLog'; Message = 'The Office 365 Management APIs service principal is disabled in this tenant, which usually means it has no licence with an audit log.' }
                } elseif ($_.Error) {
                    $Entry.Failure ??= @{ Code = $_.ErrorCode; Message = $_.Error }
                } else {
                    $Entry.Blobs += @($_.Blobs).Count
                    $ListingStart = $_.StartTime
                    $Range = $Entry.Ranges.Where({ $_.Start -eq $ListingStart }, 'First')[0]
                    if ($Range) {
                        foreach ($Blob in @($_.Blobs)) {
                            $Created = if ($Blob.contentCreated) { ([datetimeoffset]$Blob.contentCreated).UtcDateTime } else { $Range.Start }
                            if ($Created -gt $Range.ListedThrough) { $Range.ListedThrough = $Created }
                            if ($Range.Done.Contains([string]$Blob.contentId) -or $Range.Pending.ContainsKey([string]$Blob.contentId)) { continue }
                            $Key = '{0:D19}|{1}' -f $Created.Ticks, $Blob.contentId
                            $Range.Pending[[string]$Blob.contentId] = $Key
                            $null = $Range.Order.Add($Key)
                        }
                        $Range.Listed = $_.Complete -ne $false
                    }
                }
                return
            }

            $Entry = $Progress['{0}|{1}' -f $TenantId, $_.Blob.contentType]
            if ($_.Error) {
                $Entry.Failure ??= @{ Code = $_.ErrorCode ?? 'Download'; Message = $_.Error }
                return
            }
            $Total = $Totals[$TenantId]
            $Total.Records += $_.RecordCount
            $Entry.Records += $_.RecordCount
            $Records = [System.Collections.Generic.List[object]]::new([object[]]$_.Records)
            if ($Records.Count -gt 0) {
                $Total.Evaluated += $Records.Count
                $Memo ??= [pscustomobject]@{ Tenant = $Total.TenantFilter; UserLookup = $null; GroupLookup = $null; DeviceLookup = $null; ServicePrincipalLookup = $null }
                if (-not $_.TenantDone) { $Memos[$TenantId] = $Memo }
                $script:AuditRuleSearchLookups = $Memo
                # Nothing is cached for these records, so there is nothing for the engine to delete.
                $Result = Test-CIPPAuditLogRules -TenantFilter $Total.TenantFilter -Rows $Records -CallerSweepsCachePartition
                $script:AuditRuleSearchLookups = $null
                if ($Result.Error) {
                    $Entry.Failure ??= @{ Code = 'Rules'; Message = $Result.Error }
                    return
                }
                $Total.Matched += [int]$Result.MatchedLogs
                $Entry.Matched += [int]$Result.MatchedLogs
            }
            & $BlobDone $Entry $_.Blob
        }
    } catch {
        foreach ($Entry in $Progress.Values) { $Entry.Failure ??= @{ Code = 'Download'; Message = $_.Exception.Message } }
    }
    $script:AuditRuleSearchLookups = $null

    foreach ($TenantId in @($Totals.Keys)) {
        $Total = $Totals[$TenantId]
        $TenantProgress = @($Progress.Values.Where({ [string]$_.Query.TenantId -eq $TenantId -and -not $_.Subscribed }))
        foreach ($Entry in $TenantProgress) {
            # A failure keeps the blobs finished before it: the cursor stops just short of the first one not finished.
            $Reached = & $Frontier $Entry
            if ($Entry.Failure) {
                $Failures.Add(@{ Listing = $Entry.Query; Code = $Entry.Failure.Code; Message = $Entry.Failure.Message; Reached = $(if ($Reached -gt $Entry.Query.StartTime) { $Reached }) })
            } else {
                $CursorUpdates.Add(@{ PartitionKey = $Total.TenantFilter; RowKey = $Entry.Query.ContentType; LastEndUtc = $Reached; LastPolledUtc = $Now; LastSuccessUtc = $Now; Blobs = $Entry.Blobs; Records = $Entry.Records; Matched = $Entry.Matched; Attempts = 0; NextAttemptUtc = $Now; LastErrorCode = ''; LastError = '' })
            }
        }
        if ($TenantProgress.Count -gt 0) {
            Write-Information "AuditLogFeedV3: $($Total.TenantFilter) read $($Total.Records) record(s) from $(($TenantProgress.Blobs | Measure-Object -Sum).Sum) blob(s), evaluated $($Total.Evaluated), matched $($Total.Matched)"
        }
    }

    foreach ($Failure in $Failures) {
        $Listing = $Failure.Listing
        $ContentType = $Listing.ContentType
        $Cursor = ($Item.Tenants.Where({ $_.TenantFilter -eq $Listing.TenantFilter }, 'First'))[0].Cursors.$ContentType
        $Attempts = [int]$Cursor.Attempts + 1
        $Parked = $Failure.Code -in @('AuditLogDisabled', 'NoAuditLog')
        if ($Attempts -eq 1 -or [string]$Cursor.LastErrorCode -ne [string]$Failure.Code) {
            Write-LogMessage -API 'AuditLogFeedV3' -tenant $Listing.TenantFilter -message "Could not read the $ContentType audit log feed: $($Failure.Message)" -sev ($Parked ? 'Warning' : 'Error')
        }
        $Update = @{
            PartitionKey = $Listing.TenantFilter; RowKey = $ContentType; LastPolledUtc = $Now
            Attempts = $Attempts; NextAttemptUtc = ($Parked ? $Now.AddDays(1) : (Get-CippAuditLogNextAttempt -Attempts $Attempts))
            LastErrorCode = [string]$Failure.Code; LastError = [string]$Failure.Message; LastErrorUtc = $Now
        }
        if ($Failure.Reached) { $Update.LastEndUtc = $Failure.Reached }
        $CursorUpdates.Add($Update)
    }
    if ($CursorUpdates.Count -gt 0) {
        $null = Add-CIPPAzDataTableEntity @CursorTable -Entity $CursorUpdates.ToArray() -OperationType UpsertMerge
    }

    if ($Item.CycleId) {
        try {
            $CycleTable = Get-CippTable -TableName 'AuditLogFeedCycles'
            $Finished = [datetime]::UtcNow
            $null = Add-CIPPAzDataTableEntity @CycleTable -Entity @{
                PartitionKey = 'Feed'; RowKey = '{0}-{1}' -f $Item.CycleId, @($Item.Tenants)[0].TenantId; CycleId = [string]$Item.CycleId
                StartedUtc   = $Now; FinishedUtc = $Finished; DurationSeconds = [Math]::Round(($Finished - $Now).TotalSeconds, 1)
                Tenants      = $Totals.Count; Feeds = $Progress.Count
                Failed       = @($Failures.Where({ $_.Code -notin @('AuditLogDisabled', 'NoAuditLog') })).Count
                Parked       = @($Failures.Where({ $_.Code -in @('AuditLogDisabled', 'NoAuditLog') })).Count
                Blobs        = [int](($Progress.Values.Blobs | Measure-Object -Sum).Sum)
                Records      = [int](($Totals.Values.Records | Measure-Object -Sum).Sum)
                Evaluated    = [int](($Totals.Values.Evaluated | Measure-Object -Sum).Sum)
                Matched      = [int](($Totals.Values.Matched | Measure-Object -Sum).Sum)
            } -Force
        } catch {
            Write-Information "AuditLogFeedV3: could not record the cycle: $($_.Exception.Message)"
        }
    }
}
