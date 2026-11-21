function Get-CIPPCloudBackupObject {
    <#
    .SYNOPSIS
        Downloads an object (or one version of it) from a cloud backup destination as { Body; Metadata; VersionId }, or $null when it does not exist.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [string]$VersionId
    )

    switch ($Destination.Provider) {
        'AzureBlob' { Get-CIPPCloudBackupAzureObject @PSBoundParameters }
        'S3' { Get-CIPPCloudBackupS3Object @PSBoundParameters }
        default { throw [System.ArgumentException]::new("Unknown cloud backup provider '$($Destination.Provider)'.") }
    }
}
