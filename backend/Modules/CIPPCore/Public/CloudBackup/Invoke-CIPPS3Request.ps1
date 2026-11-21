function Invoke-CIPPS3Request {
    <#
    .SYNOPSIS
        Sends a SigV4-signed request to an S3 or S3-compatible cloud backup destination.
    .DESCRIPTION
        AWS buckets use virtual-hosted style unless ForcePathStyle is set or the bucket name is not DNS-safe; a custom
        Endpoint always uses path style. Returns { StatusCode; Headers; Body (byte[]); Xml } where Xml is the parsed
        body of bucket-level requests. Failures throw with the S3 error code in Exception.Data['S3ErrorCode'];
        NoSuchBucket throws ItemNotFoundException and bad destination settings throw ArgumentException.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Destination,
        [ValidateSet('GET', 'PUT', 'POST', 'DELETE', 'HEAD')]
        [string]$Method = 'GET',
        [string]$Key = '',
        [hashtable]$Query,
        [byte[]]$Body,
        [hashtable]$Headers
    )

    $Bucket = "$($Destination.Bucket)".Trim()
    $AccessKeyId = "$($Destination.AccessKeyId)".Trim()
    $Secret = "$($Destination.Secret)"
    if (-not $Bucket -or -not $AccessKeyId -or -not $Secret) {
        throw [System.ArgumentException]::new('The S3 destination needs a bucket, an access key ID and a secret access key')
    }
    if ($Bucket -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]{1,254}$') {
        throw [System.ArgumentException]::new("'$Bucket' is not a valid bucket name")
    }
    $Region = "$($Destination.Region)".Trim()
    if (-not $Region) { $Region = 'us-east-1' }
    if ($Region -notmatch '^[A-Za-z0-9-]+$') {
        throw [System.ArgumentException]::new("'$Region' is not a valid region")
    }

    $Endpoint = "$($Destination.Endpoint)".Trim()
    if ($Endpoint) {
        if ($Endpoint -notmatch '^[A-Za-z][A-Za-z0-9+.-]*://') { $Endpoint = "https://$Endpoint" }
        $EndpointUri = $null
        if (-not [uri]::TryCreate($Endpoint, [System.UriKind]::Absolute, [ref]$EndpointUri) -or $EndpointUri.Scheme -notin @('http', 'https')) {
            throw [System.ArgumentException]::new("'$($Destination.Endpoint)' is not a valid S3 endpoint URL")
        }
        $BaseUri = '{0}://{1}' -f $EndpointUri.Scheme, $EndpointUri.Authority
        $PathStyle = $true
    } else {
        $PathStyle = $Destination.ForcePathStyle -eq $true -or $Bucket -cnotmatch '^[a-z0-9][a-z0-9-]*[a-z0-9]$'
        $BaseUri = if ($PathStyle) { "https://s3.$Region.amazonaws.com" } else { "https://$Bucket.s3.$Region.amazonaws.com" }
    }

    $Segments = if ($Key) { $Key.Split('/') } else { @() }
    $EncodedSegments = foreach ($Segment in $Segments) {
        # System.Uri would collapse these segments and change the signed path
        if ($Segment -eq '.' -or $Segment -eq '..') { throw [System.ArgumentException]::new("'$Key' is not a valid object key") }
        [uri]::EscapeDataString($Segment)
    }
    $EncodedKey = [string]::Join('/', [string[]]@($EncodedSegments))
    $Path = if ($PathStyle) {
        if ($Key) { '/{0}/{1}' -f [uri]::EscapeDataString($Bucket), $EncodedKey } else { '/' + [uri]::EscapeDataString($Bucket) }
    } else { '/' + $EncodedKey }

    $QueryString = ''
    if ($Query -and $Query.Count -gt 0) {
        $SortedQuery = [System.Collections.Generic.SortedDictionary[string, string]]::new([System.StringComparer]::Ordinal)
        foreach ($Name in $Query.Keys) { $SortedQuery[[uri]::EscapeDataString($Name)] = [uri]::EscapeDataString([string]$Query[$Name]) }
        $QueryString = '?' + [string]::Join('&', [string[]]@(foreach ($Entry in $SortedQuery.GetEnumerator()) { '{0}={1}' -f $Entry.Key, $Entry.Value }))
    }
    $Uri = [uri]"$BaseUri$Path$QueryString"

    [byte[]]$PayloadBytes = $Body ?? [byte[]]::new(0)
    $SignedHeaders = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $SignedHeaders['x-amz-date'] = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ', [System.Globalization.CultureInfo]::InvariantCulture)
    $SignedHeaders['x-amz-content-sha256'] = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($PayloadBytes)).ToLowerInvariant()
    if ($Headers) { foreach ($Name in $Headers.Keys) { $SignedHeaders[$Name] = [string]$Headers[$Name] } }
    $ContentType = $SignedHeaders['Content-Type']

    $Authorization = Get-CIPPS3Signature -Method $Method -Uri $Uri -Headers $SignedHeaders -Region $Region -AccessKeyId $AccessKeyId -SecretAccessKey $Secret

    $RequestHeaders = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Entry in $SignedHeaders.GetEnumerator()) {
        if ($Entry.Key -ne 'Content-Type') { $RequestHeaders[$Entry.Key] = $Entry.Value }
    }
    $RequestHeaders['Authorization'] = $Authorization

    # Invoke-CIPPRestMethod sends byte[] bodies through Invoke-RestMethod and returns bodies as text, which corrupts binary objects
    $Request = [CIPP.CIPPConcurrentRequest]@{ Uri = $Uri.AbsoluteUri; Method = $Method; Headers = $RequestHeaders; ContentType = $ContentType; TimeoutSec = 300 }
    if ($null -ne $Body) { $Request.BodyBytes = $Body }
    $Response = [CIPP.CIPPRestClient]::SendConcurrent([CIPP.CIPPConcurrentRequest[]]@($Request), 1, 3, $PSCmdlet.PipelineStopToken)[0]

    $Target = if ($Key) { "object '$Key' in bucket '$Bucket'" } else { "bucket '$Bucket'" }
    if ($Response.StatusCode -eq 0) {
        throw "S3 $Method request for $Target failed: $($Response.Error)"
    }

    $ResponseHeaders = @{}
    foreach ($Header in $Response.Result.ResponseHeaders.GetEnumerator()) { $ResponseHeaders[$Header.Key] = $Header.Value -join ',' }
    [byte[]]$ResponseBytes = $Response.Result.ContentBytes
    if ($null -eq $ResponseBytes) { $ResponseBytes = [System.Text.Encoding]::UTF8.GetBytes([string]$Response.Result.Content) }

    $Xml = $null
    if ($ResponseBytes.Length -gt 0 -and (-not $Key -or -not $Response.IsSuccess)) {
        try {
            $Xml = [xml]::new()
            $Xml.Load([System.IO.MemoryStream]::new($ResponseBytes))
        } catch {
            $Xml = $null
        }
    }

    if (-not $Response.IsSuccess) {
        $Code = $Xml.Error.Code
        $Message = $Xml.Error.Message
        if (-not $Code) {
            $Code = if ($Response.StatusCode -eq 404) { 'NotFound' } else { "HTTP$($Response.StatusCode)" }
            $Text = [System.Text.Encoding]::UTF8.GetString($ResponseBytes, 0, [Math]::Min($ResponseBytes.Length, 300)).Trim()
            $Message = if ($Text) { $Text } else { 'No error details returned' }
        }
        $ErrorText = "S3 $Method request for $Target failed with $Code (HTTP $($Response.StatusCode)): $Message"
        $Exception = if ($Code -eq 'NoSuchBucket') {
            [System.Management.Automation.ItemNotFoundException]::new($ErrorText)
        } else {
            [System.Exception]::new($ErrorText)
        }
        $Exception.Data['S3ErrorCode'] = $Code
        $Exception.Data['StatusCode'] = $Response.StatusCode
        throw $Exception
    }

    [pscustomobject]@{
        StatusCode = $Response.StatusCode
        Headers    = $ResponseHeaders
        Body       = $ResponseBytes
        Xml        = $Xml
    }
}
