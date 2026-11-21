function Get-CIPPCloudBackupObjectList {
    <#
    .SYNOPSIS
        Lists every object under a prefix in a cloud backup destination as { Key; Size; LastModified }.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Prefix
    )

    switch ($Destination.Provider) {
        'AzureBlob' { Get-CIPPCloudBackupAzureObjectList @PSBoundParameters }
        'S3' { Get-CIPPCloudBackupS3ObjectList @PSBoundParameters }
        default { throw [System.ArgumentException]::new("Unknown cloud backup provider '$($Destination.Provider)'.") }
    }
}
