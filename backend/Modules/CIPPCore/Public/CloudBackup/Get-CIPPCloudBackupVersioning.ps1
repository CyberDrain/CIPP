function Get-CIPPCloudBackupVersioning {
    <#
    .SYNOPSIS
        Returns the versioning status of a cloud backup destination: Enabled, Suspended or Disabled.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination
    )

    switch ($Destination.Provider) {
        'AzureBlob' { Get-CIPPCloudBackupAzureVersioning @PSBoundParameters }
        'S3' { Get-CIPPCloudBackupS3Versioning @PSBoundParameters }
        default { throw [System.ArgumentException]::new("Unknown cloud backup provider '$($Destination.Provider)'.") }
    }
}
