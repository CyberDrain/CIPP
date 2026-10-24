function Get-CIPPAuditLogContent {
    <#
    .SYNOPSIS
        Lists and downloads Management Activity API content for any number of tenants and keeps the records rules can match.
    .DESCRIPTION
        Each query is @{ TenantFilter; TenantId; ContentType; StartTime; EndTime }. The range filters on when a blob was
        published (contentCreated), start inclusive and end exclusive, at most 24 hours wide and starting within the last
        7 days. Listings and downloads share one CIPPConcurrentQueue: a blob is requested as soon as the listing page
        naming it returns, and every result is handled as it finishes, so the caller's work on one blob overlaps the
        network time of the rest. Pages are followed through the NextPageUri header.

        Emits, as each completes:
          - Kind 'Listing', once per listing page: TenantFilter, TenantId, ContentType, StartTime, EndTime, Blobs (that
            page's), Complete (true on a query's last page, or on its error), StatusCode, ErrorCode (the AF code from the
            error body, or 'Token' when no token could be issued) and Error;
          - Kind 'Blob', once per blob: TenantId, Blob, Skipped (dropped by the raw check), RecordCount (records in a
            parsed blob), Records (the kept raw records), StatusCode, ErrorCode and Error.
        TenantDone is true on the last object of a tenant, once nothing of it is left in flight. At most MaxConcurrency
        responses are held at once, and a pipeline consumer holds one blob's records at a time.

        A blob whose raw JSON contains none of its tenant's rule operations is dropped without being parsed, and otherwise
        it is parsed and only the records Select-CIPPAuditLogCandidate keeps are returned. The raw check is a
        case-insensitive search for '"Operation":"<name>' (Microsoft writes compact JSON), a prefix so trailing characters
        cannot hide a match; a like pattern searches for its text before the first wildcard. It only ever lets extra
        blobs through. It is not used for a name JSON would escape (non-ASCII, quote, backslash) or a pattern that starts
        with a wildcard, and never drops a blob holding an item named Operation, which the engine would flatten over the
        record's own. Prefilters maps a tenant id to its Get-CIPPAuditLogPrefilter result; a tenant without one, or with
        $null, keeps every record.

        Tokens are delegated: the SAM app holds ActivityFeed.Read only as a delegated scope.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Queries,
        [hashtable]$Prefilters = @{},
        [int]$MaxConcurrency = 32
    )

    $UserAgent = Get-CippUserAgent
    $Queue = [CIPP.CIPPConcurrentQueue]::new($MaxConcurrency, 2)
    # Queue index -> the listing a page belongs to, or the blob result a download fills.
    $Work = @{}
    # Tenant id -> objects still to be emitted for it.
    $Open = @{}
    $Tokens = @{}
    $TokenErrors = @{}
    $RawChecks = @{}

    foreach ($Query in $Queries) { $Open[[string]$Query.TenantId] = 1 + [int]$Open[[string]$Query.TenantId] }
    foreach ($Query in $Queries) {
        $TenantId = [string]$Query.TenantId
        $Listing = [pscustomobject]@{
            Kind         = 'Listing'
            TenantFilter = $Query.TenantFilter
            TenantId     = $Query.TenantId
            ContentType  = $Query.ContentType
            StartTime    = $Query.StartTime
            EndTime      = $Query.EndTime
            Blobs        = [System.Collections.Generic.List[object]]::new()
            Complete     = $true
            StatusCode   = 0
            ErrorCode    = $null
            Error        = $null
            TenantDone   = $false
        }
        if (-not $Tokens.ContainsKey($TenantId)) {
            try {
                $Tokens[$TenantId] = (Get-GraphToken -tenantid $TenantId -scope 'https://manage.office.com/.default').Authorization
            } catch {
                $Tokens[$TenantId] = $null
                $TokenErrors[$TenantId] = $_.Exception.Message
            }
        }
        if (-not $Tokens[$TenantId]) {
            $Listing.ErrorCode = 'Token'
            $Listing.Error = $TokenErrors[$TenantId] ?? 'No token for the Office 365 Management API'
            $Open[$TenantId]--
            $Listing.TenantDone = $Open[$TenantId] -eq 0
            $Listing
            continue
        }
        $Request = [CIPP.CIPPConcurrentRequest]::new()
        $Request.Uri = 'https://manage.office.com/api/v1.0/{0}/activity/feed/subscriptions/content?contentType={1}&startTime={2:yyyy-MM-ddTHH:mm:ss}&endTime={3:yyyy-MM-ddTHH:mm:ss}&PublisherIdentifier={4}' -f $TenantId, $Query.ContentType, ([datetime]$Query.StartTime).ToUniversalTime(), ([datetime]$Query.EndTime).ToUniversalTime(), $env:TenantID
        $Request.Headers = [System.Collections.Generic.Dictionary[string, string]]::new()
        $Request.Headers['Authorization'] = $Tokens[$TenantId]
        $Request.Headers['User-Agent'] = $UserAgent
        $Work[$Queue.Add($Request)] = @{ Listing = $Listing }
    }

    while ($null -ne ($Done = $Queue.Next())) {
        $Entry = $Work[$Done.Index]
        $Work.Remove($Done.Index)

        if ($Entry.Listing) {
            $Listing = $Entry.Listing
            $TenantId = [string]$Listing.TenantId
            $Listing.StatusCode = $Done.StatusCode
            if ($Done.Error) {
                $Listing.Error = $Done.Error
            } elseif (-not $Done.IsSuccess) {
                $Body = if ($Done.Result.HasContent) { $Done.Result.Content }
                $Parsed = try { [CIPP.CippJson]::ConvertFromJson([string]$Body) } catch { $null }
                $Listing.ErrorCode = $Parsed.error.code
                $Listing.Error = $Parsed.error.message ?? $Body ?? "HTTP $($Done.StatusCode)"
            } else {
                if (-not $RawChecks.ContainsKey($TenantId)) {
                    $Operations = $Prefilters[$TenantId].Operations
                    $Needles = @(foreach ($Operation in $Operations) { ($Operation -split '[*?\[]', 2)[0] })
                    $RawChecks[$TenantId] = if ($null -ne $Operations -and $Needles.Where({ $_ -notmatch '^[\x20-\x7E]+$' -or $_.Contains('"') -or $_.Contains('\') }, 'First').Count -eq 0) { , $Needles }
                }
                # The next page goes in ahead of this page's downloads, so a long listing is not read behind them.
                $NextPage = $null
                $HasNext = $Done.Result.ResponseHeaders.TryGetValue('NextPageUri', [ref]$NextPage) -and $NextPage
                if ($HasNext) {
                    $Request = [CIPP.CIPPConcurrentRequest]::new()
                    $Request.Uri = [string]$NextPage[0]
                    if ($Request.Uri -notmatch 'PublisherIdentifier=') { $Request.Uri = '{0}&PublisherIdentifier={1}' -f $Request.Uri, $env:TenantID }
                    $Request.Headers = [System.Collections.Generic.Dictionary[string, string]]::new()
                    $Request.Headers['Authorization'] = $Tokens[$TenantId]
                    $Request.Headers['User-Agent'] = $UserAgent
                    $Work[$Queue.Add($Request)] = $Entry
                }
                $PageBlobs = [System.Collections.Generic.List[object]]::new()
                if ($Done.Result.HasContent) {
                    foreach ($Blob in [CIPP.CippJson]::ConvertFromResponse($Done.Result)) {
                        $PageBlobs.Add($Blob)
                        $Request = [CIPP.CIPPConcurrentRequest]::new()
                        $Request.Uri = '{0}?PublisherIdentifier={1}' -f $Blob.contentUri, $env:TenantID
                        $Request.Headers = [System.Collections.Generic.Dictionary[string, string]]::new()
                        $Request.Headers['Authorization'] = $Tokens[$TenantId]
                        $Request.Headers['User-Agent'] = $UserAgent
                        $Open[$TenantId]++
                        $Work[$Queue.Add($Request)] = @{ Result = [pscustomobject]@{ Kind = 'Blob'; TenantId = $TenantId; Blob = $Blob; Skipped = $false; RecordCount = 0; Records = @(); StatusCode = 0; ErrorCode = $null; Error = $null; TenantDone = $false } }
                    }
                }
                if ($HasNext) {
                    [pscustomobject]@{
                        Kind = 'Listing'; TenantFilter = $Listing.TenantFilter; TenantId = $Listing.TenantId; ContentType = $Listing.ContentType
                        StartTime = $Listing.StartTime; EndTime = $Listing.EndTime; Blobs = $PageBlobs; Complete = $false
                        StatusCode = $Done.StatusCode; ErrorCode = $null; Error = $null; TenantDone = $false
                    }
                    continue
                }
                $Listing.Blobs = $PageBlobs
            }
            $Listing.Complete = $true
            $Open[$TenantId]--
            $Listing.TenantDone = $Open[$TenantId] -eq 0
            $Listing
            continue
        }

        $Result = $Entry.Result
        $Result.StatusCode = $Done.StatusCode
        if ($Done.Error) {
            $Result.Error = $Done.Error
        } elseif (-not $Done.IsSuccess) {
            $Body = if ($Done.Result.HasContent) { $Done.Result.Content }
            $Parsed = try { [CIPP.CippJson]::ConvertFromJson([string]$Body) } catch { $null }
            $Result.ErrorCode = $Parsed.error.code
            $Result.Error = $Parsed.error.message ?? $Body ?? "HTTP $($Done.StatusCode)"
        } elseif ($Done.Result.HasContent) {
            try {
                $Found = $true
                if ($null -ne $RawChecks[$Result.TenantId]) {
                    # Methods called ON the blob are free; passing it INTO a .NET method copies it about three times.
                    $Json = $Done.Result.Content
                    $Found = $Json.IndexOf('"Name":"Operation"', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
                    foreach ($Needle in $RawChecks[$Result.TenantId]) {
                        if ($Json.IndexOf(('"Operation":"{0}' -f $Needle), [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { $Found = $true; break }
                    }
                    $Json = $null
                }
                if ($Found) {
                    # The response object, not its text, so the blob is parsed from its bytes without a string copy.
                    $Records = @([CIPP.CippJson]::ConvertFromResponse($Done.Result))
                    $Result.RecordCount = $Records.Count
                    $Result.Records = @(Select-CIPPAuditLogCandidate -Prefilter $Prefilters[$Result.TenantId] -Records $Records)
                    $Records = $null
                } else {
                    $Result.Skipped = $true
                }
            } catch {
                $Result.Error = "Could not parse the blob: $($_.Exception.Message)"
            }
        }
        $Done = $null
        $Open[$Result.TenantId]--
        $Result.TenantDone = $Open[$Result.TenantId] -eq 0
        $Result
    }
}
