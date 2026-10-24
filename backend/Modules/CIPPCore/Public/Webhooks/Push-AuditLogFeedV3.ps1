function Push-AuditLogFeedV3 {
    <#
    .SYNOPSIS
        Polls the Management Activity API feed for a chunk of tenants and stages new records for processing.
    .DESCRIPTION
        Per tenant and content type, lists the blobs published since the AuditLogFeedCursor row (the last hour for a new
        cursor, at most 24 hours per poll, never more than 7 days back). Get-CIPPAuditLogContent lists and downloads the
        chunk's blobs through one request queue and hands each blob over as it arrives, so evaluating and storing one
        blob overlaps the network time of the rest. Records Get-CIPPAuditLogPrefilter rules out are dropped; the rest of
        a blob are run through Test-CIPPAuditLogRules -EvaluateOnly, and only the records a rule matches are stored
        unchanged in CacheWebhooks under '<tenant>|feed-<timestamp>', keyed by record Id. If the engine fails for a
        tenant, all its candidates are stored, so processing decides. A tenant with stored records gets an
        AuditLogCoverage row (Type Feed) already in State Processing, since this run's post-execution evaluates them again
        and sends the alerts; Start-AuditLogFeedV3's sweep recovers it if that never happens.

        Returns one [pscustomobject]@{ TenantFilter; SearchId; WindowRowKey; RecordCount } per stored window, for the
        AuditLogFeedProcessV3 post-execution to queue without reading the ledger back. The task's totals and timing are
        written to AuditLogFeedCycles under the item's CycleId, and each cursor keeps its last read's counts.

        A cursor advances only when its listing and every blob downloaded, so a failure re-reads the same range next
        cycle; the record-Id upsert and the AuditLogs claim keep that from alerting twice. AF20022 (no subscription) and
        AF20023 (subscription disabled) start one. A tenant with no audit log to read - the start call reports the
        tenant missing (unified audit log ingestion off), or the token fails with AADSTS500014 (the Office 365
        Management APIs service principal is disabled, as in unlicensed tenants) - is parked for a day with the reason
        on the cursor row. Other failures back off with Get-CippAuditLogNextAttempt.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $Now = [datetime]::UtcNow
    # Blobs published in the last few minutes can still be missing from a listing.
    $End = $Now.AddMinutes(-5)
    $Floor = $Now.AddDays(-7).AddMinutes(10)
    $Stamp = $Now.ToString('yyyyMMddHHmmss')
    $CursorTable = Get-CippTable -TableName 'AuditLogFeedCursor'
    $CacheTable = Get-CippTable -TableName 'CacheWebhooks'
    $Ledger = Get-CippTable -TableName 'AuditLogCoverage'

    $Queries = foreach ($Tenant in $Item.Tenants) {
        foreach ($ContentType in $Tenant.ContentTypes) {
            $LastEnd = $Tenant.Cursors.$ContentType.LastEndUtc
            $Start = if ($LastEnd) { ([datetimeoffset]$LastEnd).UtcDateTime } else { $End.AddHours(-1) }
            if ($Start -lt $Floor) {
                Write-LogMessage -API 'AuditLogFeedV3' -tenant $Tenant.TenantFilter -message "The $ContentType feed was last read at $($Start.ToString('o')). Content older than 7 days is no longer available and was skipped." -sev Warning
                $Start = $Floor
            }
            $QueryEnd = if ($Start.AddHours(24) -lt $End) { $Start.AddHours(24) } else { $End }
            if ($QueryEnd -gt $Start) {
                @{ TenantFilter = $Tenant.TenantFilter; TenantId = $Tenant.TenantId; ContentType = $ContentType; StartTime = $Start; EndTime = $QueryEnd }
            }
        }
    }
    $Queries = @($Queries)
    if ($Queries.Count -eq 0) { return }

    $CursorUpdates = [System.Collections.Generic.List[object]]::new()
    $Failures = [System.Collections.Generic.List[object]]::new()
    # One entry per query, keyed '<tenant id>|<content type>', so the cursor decision never depends on arrival order.
    $Progress = @{}
    foreach ($Query in $Queries) { $Progress['{0}|{1}' -f $Query.TenantId, $Query.ContentType] = @{ Query = $Query; Blobs = 0; Records = 0; Stored = 0; Failure = $null; Subscribed = $false } }
    $Totals = @{}
    $Prefilters = @{}
    foreach ($Tenant in $Item.Tenants) {
        $Totals[[string]$Tenant.TenantId] = @{ TenantFilter = $Tenant.TenantFilter; Records = 0; Evaluated = 0; Stored = 0; Opened = $false }
        if ($Tenant.ContentTypes) { $Prefilters[[string]$Tenant.TenantId] = Get-CIPPAuditLogPrefilter -TenantFilter $Tenant.TenantFilter }
    }
    # The engine's directory memo, one per tenant: blobs of several tenants interleave, and a tenant's is dropped once
    # its last blob is in.
    $Memos = @{}

    try {
        Get-CIPPAuditLogContent -Queries $Queries -Prefilters $Prefilters | ForEach-Object {
            $TenantId = [string]$_.TenantId
            $Memo = $Memos[$TenantId]
            if ($_.TenantDone) { $Memos.Remove($TenantId) }

            if ($_.Kind -eq 'Listing') {
                $Entry = $Progress['{0}|{1}' -f $TenantId, $_.ContentType]
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
                    $Entry.Blobs = $_.Blobs.Count
                }
                return
            }

            $Key = '{0}|{1}' -f $TenantId, $_.Blob.contentType
            if ($_.Error) {
                $Progress[$Key].Failure ??= @{ Code = $_.ErrorCode ?? 'Download'; Message = $_.Error }
                return
            }
            $Total = $Totals[$TenantId]
            $Total.Records += $_.RecordCount
            $Progress[$Key].Records += $_.RecordCount
            $Records = [System.Collections.Generic.List[object]]::new([object[]]$_.Records)
            if ($Records.Count -eq 0) { return }
            $Total.Evaluated += $Records.Count
            $Memo ??= [pscustomobject]@{ Tenant = $Total.TenantFilter; UserLookup = $null; GroupLookup = $null; DeviceLookup = $null; ServicePrincipalLookup = $null }
            if (-not $_.TenantDone) { $Memos[$TenantId] = $Memo }
            $script:AuditRuleSearchLookups = $Memo
            $Matched = [System.Collections.Generic.Dictionary[string, string]]::new()
            # One call per blob: a blob holds a few hundred records and the prefilter leaves a handful of them.
            $Result = Test-CIPPAuditLogRules -TenantFilter $Total.TenantFilter -Rows $Records -EvaluateOnly
            if ($Result.Error) {
                Write-Information "AuditLogFeedV3: rule evaluation failed for $($Total.TenantFilter), storing every candidate: $($Result.Error)"
                foreach ($Record in $Records) { if ($Record.Id) { $Matched[[string]$Record.Id] = [CIPP.CippJson]::ToJson($Record, 20) ?? (ConvertTo-Json -InputObject $Record -Compress -Depth 20) } }
            } else {
                # A matched record carries its raw record as AuditRecord JSON; a record two rules match appears twice.
                foreach ($Data in @($Result.DataToProcess)) { if ($Data.Id) { $Matched[[string]$Data.Id] = [string]$Data.AuditRecord } }
            }
            $script:AuditRuleSearchLookups = $null
            if ($Matched.Count -eq 0) { return }
            $Rows = foreach ($Pair in $Matched.GetEnumerator()) {
                @{
                    PartitionKey          = "$($Total.TenantFilter)|feed-$Stamp"
                    RowKey                = $Pair.Key
                    TenantFilter          = $Total.TenantFilter
                    SearchId              = "feed-$Stamp"
                    JSON                  = $Pair.Value
                    CippProcessing        = $false
                    CippProcessingStarted = ''
                }
            }
            try {
                # A tenant's window is in the ledger before its first row is stored, so a crash mid-store leaves the
                # sweep a window to process rather than rows nothing reads; this run's final ledger write replaces it.
                if (-not $Total.Opened) {
                    $null = Add-CIPPAzDataTableEntity @Ledger -Entity @{ PartitionKey = $Total.TenantFilter; RowKey = "FEED-$Stamp"; Type = 'Feed'; State = 'Storing'; SearchId = "feed-$Stamp"; CycleId = [string]$Item.CycleId; CreatedUtc = $Now; Attempts = 0 } -Force
                    $Total.Opened = $true
                }
                $null = Add-CIPPAzDataTableEntity @CacheTable -Entity @($Rows) -Force
                $Total.Stored += $Matched.Count
                $Progress[$Key].Stored += $Matched.Count
            } catch {
                $Progress[$Key].Failure ??= @{ Code = 'Store'; Message = $_.Exception.Message }
            }
        }
    } catch {
        foreach ($Entry in $Progress.Values) { $Entry.Failure ??= @{ Code = 'Download'; Message = $_.Exception.Message } }
    }
    $script:AuditRuleSearchLookups = $null

    foreach ($TenantId in @($Totals.Keys)) {
        $Total = $Totals[$TenantId]
        $TenantProgress = @($Progress.Values.Where({ [string]$_.Query.TenantId -eq $TenantId -and -not $_.Subscribed }))
        if ($TenantProgress.Count -eq 0) { continue }
        if ($Total.Stored -gt 0) {
            try {
                $null = Add-CIPPAzDataTableEntity @Ledger -Entity @{
                    PartitionKey = $Total.TenantFilter; RowKey = "FEED-$Stamp"; Type = 'Feed'; State = 'Processing'; SearchId = "feed-$Stamp"; CycleId = [string]$Item.CycleId
                    WindowStart  = ($TenantProgress.Query.StartTime | Measure-Object -Minimum).Minimum; WindowEnd = ($TenantProgress.Query.EndTime | Measure-Object -Maximum).Maximum
                    RecordCount  = [int]$Total.Records; EvaluatedCount = [int]$Total.Evaluated; CandidateCount = [int]$Total.Stored; CreatedUtc = $Now; DownloadedUtc = $Now; Attempts = 0
                } -Force
                [pscustomobject]@{ TenantFilter = $Total.TenantFilter; SearchId = "feed-$Stamp"; WindowRowKey = "FEED-$Stamp"; RecordCount = [int]$Total.Stored }
            } catch {
                foreach ($Entry in $TenantProgress) { $Entry.Failure ??= @{ Code = 'Store'; Message = $_.Exception.Message } }
            }
        }
        foreach ($Entry in $TenantProgress) {
            if ($Entry.Failure) {
                $Failures.Add(@{ Listing = $Entry.Query; Code = $Entry.Failure.Code; Message = $Entry.Failure.Message })
            } else {
                $CursorUpdates.Add(@{ PartitionKey = $Total.TenantFilter; RowKey = $Entry.Query.ContentType; LastEndUtc = $Entry.Query.EndTime; LastPolledUtc = $Now; LastSuccessUtc = $Now; Blobs = $Entry.Blobs; Records = $Entry.Records; Stored = $Entry.Stored; Attempts = 0; NextAttemptUtc = $Now; LastErrorCode = ''; LastError = '' })
            }
        }
        Write-Information "AuditLogFeedV3: $($Total.TenantFilter) read $($Total.Records) record(s) from $(($TenantProgress.Blobs | Measure-Object -Sum).Sum) blob(s), stored $($Total.Stored)"
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
        $CursorUpdates.Add(@{
                PartitionKey = $Listing.TenantFilter; RowKey = $ContentType; LastPolledUtc = $Now
                Attempts = $Attempts; NextAttemptUtc = ($Parked ? $Now.AddDays(1) : (Get-CippAuditLogNextAttempt -Attempts $Attempts))
                LastErrorCode = [string]$Failure.Code; LastError = [string]$Failure.Message; LastErrorUtc = $Now
            })
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
                Tenants      = $Totals.Count; Feeds = $Queries.Count
                Failed       = @($Failures.Where({ $_.Code -notin @('AuditLogDisabled', 'NoAuditLog') })).Count
                Parked       = @($Failures.Where({ $_.Code -in @('AuditLogDisabled', 'NoAuditLog') })).Count
                Blobs        = [int](($Progress.Values.Blobs | Measure-Object -Sum).Sum)
                Records      = [int](($Totals.Values.Records | Measure-Object -Sum).Sum)
                Evaluated    = [int](($Totals.Values.Evaluated | Measure-Object -Sum).Sum)
                Stored       = [int](($Totals.Values.Stored | Measure-Object -Sum).Sum)
            } -Force
        } catch {
            Write-Information "AuditLogFeedV3: could not record the cycle: $($_.Exception.Message)"
        }
    }
}
