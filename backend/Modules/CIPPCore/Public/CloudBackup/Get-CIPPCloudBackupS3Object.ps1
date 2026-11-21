function Get-CIPPCloudBackupS3Object {
    <#
    .SYNOPSIS
        Downloads an object (or one version of it) from an S3 cloud backup destination; returns { Body; Metadata; VersionId } or $null when it is missing.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Destination,
        [Parameter(Mandatory)][string]$Key,
        [string]$VersionId
    )

    $Query = @{}
    if ($VersionId) { $Query['versionId'] = $VersionId }
    try {
        $Response = Invoke-CIPPS3Request -Destination $Destination -Method GET -Key $Key -Query $Query
    } catch {
        if ($_.Exception.Data['S3ErrorCode'] -in @('NoSuchKey', 'NotFound')) { return $null }
        throw
    }

    $Metadata = @{}
    foreach ($Name in $Response.Headers.Keys) {
        if ($Name.StartsWith('x-amz-meta-', [System.StringComparison]::OrdinalIgnoreCase)) {
            $Metadata[$Name.Substring(11)] = $Response.Headers[$Name]
        }
    }
    [pscustomobject]@{ Body = $Response.Body; Metadata = $Metadata; VersionId = $Response.Headers['x-amz-version-id'] }
}
