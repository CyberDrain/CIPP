function Remove-CIPPCloudBackupS3Object {
    <#
    .SYNOPSIS
        Deletes an object, or one version of it, from an S3 cloud backup destination; without -VersionId a versioned bucket adds a delete marker. A missing object is not an error.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]$Destination,
        [Parameter(Mandatory)][string]$Key,
        [string]$VersionId
    )

    if ($PSCmdlet.ShouldProcess($Key, 'Delete S3 object')) {
        try {
            $Query = @{}
            if ($VersionId) { $Query['versionId'] = $VersionId }
            $null = Invoke-CIPPS3Request -Destination $Destination -Method DELETE -Key $Key -Query $Query
        } catch {
            if ($_.Exception.Data['S3ErrorCode'] -notin @('NoSuchKey', 'NotFound')) { throw }
        }
    }
}
