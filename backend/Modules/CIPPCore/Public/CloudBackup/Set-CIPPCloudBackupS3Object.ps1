function Set-CIPPCloudBackupS3Object {
    <#
    .SYNOPSIS
        Uploads an object to an S3 cloud backup destination, with metadata as x-amz-meta-* headers, and returns { Key; Bytes; VersionId }.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Destination,
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][AllowEmptyCollection()][byte[]]$Body,
        [string]$ContentType = 'application/octet-stream',
        [hashtable]$Metadata
    )

    $Headers = @{ 'Content-Type' = $ContentType }
    if ($Metadata) {
        foreach ($Name in $Metadata.Keys) {
            $Value = [string]$Metadata[$Name]
            if ($Name -notmatch '^[A-Za-z0-9_-]+$' -or $Value -notmatch '^[\x20-\x7E]*$') {
                throw [System.ArgumentException]::new("Metadata '$Name' needs a name of letters, digits, '-' or '_' and a printable ASCII value")
            }
            $Headers["x-amz-meta-$Name"] = $Value
        }
    }
    if ($PSCmdlet.ShouldProcess($Key, 'Upload S3 object')) {
        $Response = Invoke-CIPPS3Request -Destination $Destination -Method PUT -Key $Key -Body $Body -Headers $Headers
        $VersionId = $Response.Headers.'x-amz-version-id'
        [pscustomobject]@{
            Key       = $Key
            Bytes     = [int64]$Body.Length
            VersionId = if ($VersionId -and $VersionId -ne 'null') { $VersionId } else { $null }
        }
    }
}
