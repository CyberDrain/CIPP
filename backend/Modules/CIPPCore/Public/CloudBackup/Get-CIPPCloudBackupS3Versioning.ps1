function Get-CIPPCloudBackupS3Versioning {
    <#
    .SYNOPSIS
        Returns the bucket versioning status of an S3 cloud backup destination: Enabled, Suspended or Disabled.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]$Destination
    )

    $Status = (Invoke-CIPPS3Request -Destination $Destination -Method GET -Query @{ versioning = '' }).Xml.VersioningConfiguration.Status
    if ($Status -in @('Enabled', 'Suspended')) { [string]$Status } else { 'Disabled' }
}
