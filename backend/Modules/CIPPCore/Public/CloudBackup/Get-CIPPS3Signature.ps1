function Get-CIPPS3Signature {
    <#
    .SYNOPSIS
        Builds the AWS Signature Version 4 Authorization header value for an S3 request.
    .DESCRIPTION
        Signs host plus every header in -Headers, which must hold x-amz-date and x-amz-content-sha256. The path and
        query of -Uri must already be URI-encoded the way S3 expects (each path segment once, '/' kept).
    .FUNCTIONALITY
        Internal
    .LINK
        https://docs.aws.amazon.com/AmazonS3/latest/API/sig-v4-header-based-auth.html
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)][string]$Method,
        [Parameter(Mandatory)][uri]$Uri,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Headers,
        [Parameter(Mandatory)][string]$Region,
        [Parameter(Mandatory)][string]$AccessKeyId,
        [Parameter(Mandatory)][string]$SecretAccessKey,
        [string]$Service = 's3'
    )

    $AmzDate = [string]$Headers['x-amz-date']
    $PayloadHash = [string]$Headers['x-amz-content-sha256']
    if ($AmzDate -notmatch '^\d{8}T\d{6}Z$' -or -not $PayloadHash) {
        throw [System.ArgumentException]::new('The headers to sign need x-amz-date and x-amz-content-sha256')
    }
    $Scope = '{0}/{1}/{2}/aws4_request' -f $AmzDate.Substring(0, 8), $Region, $Service

    $CanonicalHeaders = [System.Collections.Generic.SortedDictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $CanonicalHeaders['host'] = $Uri.Authority
    foreach ($Name in $Headers.Keys) {
        $CanonicalHeaders[$Name.ToLowerInvariant()] = ([string]$Headers[$Name]).Trim() -replace '\s+', ' '
    }

    $CanonicalQuery = [System.Collections.Generic.SortedDictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($Pair in $Uri.Query.TrimStart('?').Split('&', [System.StringSplitOptions]::RemoveEmptyEntries)) {
        $Parts = $Pair.Split('=', 2)
        $Value = if ($Parts.Count -gt 1) { [uri]::EscapeDataString([uri]::UnescapeDataString($Parts[1])) } else { '' }
        $CanonicalQuery.Add([uri]::EscapeDataString([uri]::UnescapeDataString($Parts[0])), $Value)
    }

    $SignedHeaders = [string]::Join(';', $CanonicalHeaders.Keys)
    $CanonicalRequest = [string]::Join("`n", @(
            $Method.ToUpperInvariant()
            $(if ($Uri.AbsolutePath) { $Uri.AbsolutePath } else { '/' })
            [string]::Join('&', [string[]]@(foreach ($Entry in $CanonicalQuery.GetEnumerator()) { '{0}={1}' -f $Entry.Key, $Entry.Value }))
            foreach ($Entry in $CanonicalHeaders.GetEnumerator()) { '{0}:{1}' -f $Entry.Key, $Entry.Value }
            ''
            $SignedHeaders
            $PayloadHash
        ))

    $Utf8 = [System.Text.Encoding]::UTF8
    $StringToSign = [string]::Join("`n", @(
            'AWS4-HMAC-SHA256'
            $AmzDate
            $Scope
            [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Utf8.GetBytes($CanonicalRequest))).ToLowerInvariant()
        ))

    $SigningKey = $Utf8.GetBytes("AWS4$SecretAccessKey")
    foreach ($Part in @($AmzDate.Substring(0, 8), $Region, $Service, 'aws4_request')) {
        $SigningKey = [System.Security.Cryptography.HMACSHA256]::HashData($SigningKey, $Utf8.GetBytes($Part))
    }
    $Signature = [Convert]::ToHexString([System.Security.Cryptography.HMACSHA256]::HashData($SigningKey, $Utf8.GetBytes($StringToSign))).ToLowerInvariant()

    'AWS4-HMAC-SHA256 Credential={0}/{1},SignedHeaders={2},Signature={3}' -f $AccessKeyId, $Scope, $SignedHeaders, $Signature
}
