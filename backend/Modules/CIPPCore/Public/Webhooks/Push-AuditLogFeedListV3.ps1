function Push-AuditLogFeedListV3 {
    <#
    .SYNOPSIS
        Lists the feeds of a group of tenants and records one AuditLogFeedBlobs row per blob to download.
    .DESCRIPTION
        The tenants' due content types are listed 20 at a time (Get-CIPPAuditLogContent -ListOnly), each over the round's
        window from its cursor's ListedThroughUtc, or LastEndUtc before the first listing (Get-CIPPAuditLogFeedWindow:
        at most 3 hours, never more than 6 hours back). Each listing page's blobs are upserted as they arrive
        (PartitionKey tenant, RowKey '<created ticks>$<contentId>'), so listing a range again only rewrites its rows. A
        feed listed to the end moves ListedThroughUtc to the window's end; AuditLogFeedFanOutV3 then batches the rows.

        AF20022 (no subscription) and AF20023 (subscription disabled) start one. A tenant with no audit log to read is
        parked for a day; other failures back off with Get-CippAuditLogNextAttempt and the range is listed again later.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $Now = [datetime]::UtcNow
    $CursorTable = Get-CippTable -TableName 'AuditLogFeedCursor'
    $BlobTable = Get-CippTable -TableName 'AuditLogFeedBlobs'
    $Queries = foreach ($Tenant in $Item.Tenants) {
        foreach ($ContentType in $Tenant.ContentTypes) {
            $Cursor = $Tenant.Cursors.$ContentType
            $Window = Get-CIPPAuditLogFeedWindow -LastEndUtc ($Cursor.ListedThroughUtc ?? $Cursor.LastEndUtc) -Now $Now
            if (-not $Window) { continue }
            if ($Window.Skipped) {
                Write-LogMessage -API 'AuditLogFeedV3' -tenant $Tenant.TenantFilter -message "The $ContentType feed was last read at $($Window.Skipped.ToString('o')). Only the last 6 hours are read, so the content before $($Window.Start.ToString('o')) was skipped." -sev Warning
            }
            @{ TenantFilter = $Tenant.TenantFilter; TenantId = $Tenant.TenantId; ContentType = $ContentType; StartTime = $Window.Start; EndTime = $Window.End }
        }
    }
    $Queries = @($Queries)
    if ($Queries.Count -eq 0) { return }

    # '<tenant id>|<content type>' -> the feed's listing state.
    $Feeds = @{}
    foreach ($Query in $Queries) { $Feeds['{0}|{1}' -f $Query.TenantId, $Query.ContentType] = @{ Query = $Query; Blobs = 0; Listed = $false; Failure = $null; Subscribed = $false } }
    try {
        Get-CIPPAuditLogContent -Queries $Queries -ListOnly -MaxConcurrency 20 | ForEach-Object {
            $Feed = $Feeds['{0}|{1}' -f $_.TenantId, $_.ContentType]
            if ($Feed.Subscribed) { return }
            if ($_.ErrorCode -in @('AF20022', 'AF20023')) {
                try {
                    $null = New-GraphPOSTRequest -type POST -uri ('https://manage.office.com/api/v1.0/{0}/activity/feed/subscriptions/start?contentType={1}&PublisherIdentifier={2}' -f $_.TenantId, $_.ContentType, $env:TenantID) -body '{}' -scope 'https://manage.office.com/.default' -tenantid $_.TenantId -NoAuthCheck $true
                    Write-LogMessage -API 'AuditLogFeedV3' -tenant $_.TenantFilter -message "Started the $($_.ContentType) audit log subscription. Microsoft can take up to 12 hours to publish the first content." -sev Info
                    $Feed.Subscribed = $true
                } catch {
                    $Feed.Failure ??= if ($_.Exception.Message -match 'Tenant .+ does not exist') {
                        @{ Code = 'AuditLogDisabled'; Message = 'Unified audit logging is turned off for this tenant. Turn it on with the AuditLog standard; Microsoft can take up to 12 hours to publish content after the subscription starts.' }
                    } else {
                        @{ Code = 'SubscriptionStart'; Message = $_.Exception.Message }
                    }
                }
                return
            }
            if ($_.ErrorCode -eq 'Token' -and $_.Error -match 'AADSTS500014') {
                $Feed.Failure ??= @{ Code = 'NoAuditLog'; Message = 'The Office 365 Management APIs service principal is disabled in this tenant, which usually means it has no licence with an audit log.' }
                return
            }
            if ($_.Error) { $Feed.Failure ??= @{ Code = $_.ErrorCode; Message = $_.Error }; return }
            $Rows = @(foreach ($Blob in $_.Blobs) {
                    $Created = if ($Blob.contentCreated) { ([datetimeoffset]$Blob.contentCreated).UtcDateTime } else { $Feed.Query.StartTime }
                    @{
                        PartitionKey = [string]$Feed.Query.TenantFilter; RowKey = '{0:D19}${1}' -f $Created.Ticks, $Blob.contentId
                        TenantId = [string]$Feed.Query.TenantId; ContentType = [string]$Feed.Query.ContentType; ContentUri = [string]$Blob.contentUri
                        ContentId = [string]$Blob.contentId; CreatedUtc = $Created; Attempts = 0
                    }
                })
            if ($Rows.Count -gt 0) {
                Add-CIPPAzDataTableEntity @BlobTable -Entity $Rows -Force
                $Feed.Blobs += $Rows.Count
            }
            if ($_.Complete) { $Feed.Listed = $true }
        }
    } catch {
        foreach ($Feed in $Feeds.Values) { $Feed.Failure ??= @{ Code = 'Listing'; Message = $_.Exception.Message } }
    }

    $CursorUpdates = foreach ($Feed in $Feeds.Values) {
        $Query = $Feed.Query
        if ($Feed.Subscribed -or ($Feed.Listed -and -not $Feed.Failure)) {
            @{ PartitionKey = $Query.TenantFilter; RowKey = $Query.ContentType; ListedThroughUtc = $Query.EndTime; LastPolledUtc = $Now; LastSuccessUtc = $Now; Blobs = $Feed.Blobs; Attempts = 0; NextAttemptUtc = $Now; LastErrorCode = ''; LastError = '' }
            continue
        }
        $Failure = $Feed.Failure ?? @{ Code = 'Listing'; Message = 'The listing did not finish' }
        $ContentType = $Query.ContentType
        $Cursor = ($Item.Tenants.Where({ $_.TenantFilter -eq $Query.TenantFilter }, 'First'))[0].Cursors.$ContentType
        $Attempts = [int]$Cursor.Attempts + 1
        $Parked = $Failure.Code -in @('AuditLogDisabled', 'NoAuditLog')
        if ($Attempts -eq 1 -or [string]$Cursor.LastErrorCode -ne [string]$Failure.Code) {
            Write-LogMessage -API 'AuditLogFeedV3' -tenant $Query.TenantFilter -message "Could not read the $($Query.ContentType) audit log feed: $($Failure.Message)" -sev ($Parked ? 'Warning' : 'Error')
        }
        @{
            PartitionKey = $Query.TenantFilter; RowKey = $Query.ContentType; LastPolledUtc = $Now
            Attempts = $Attempts; NextAttemptUtc = ($Parked ? $Now.AddDays(1) : (Get-CippAuditLogNextAttempt -Attempts $Attempts))
            LastErrorCode = [string]$Failure.Code; LastError = [string]$Failure.Message; LastErrorUtc = $Now
        }
    }
    $CursorUpdates = @($CursorUpdates)
    if ($CursorUpdates.Count -gt 0) { $null = Add-CIPPAzDataTableEntity @CursorTable -Entity $CursorUpdates -OperationType UpsertMerge }
    Write-Information "AuditLogFeedListV3: listed $(@($Feeds.Values).Count) feed(s) of $(@($Item.Tenants).Count) tenant(s), $((@($Feeds.Values).Blobs | Measure-Object -Sum).Sum) blob(s), $(@($Feeds.Values.Where({ $_.Failure })).Count) failed"
}
