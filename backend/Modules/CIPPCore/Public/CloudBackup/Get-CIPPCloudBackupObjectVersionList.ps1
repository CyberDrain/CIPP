function Get-CIPPCloudBackupObjectVersionList {
    <#
    .SYNOPSIS
        Lists every version and delete marker under a prefix as { Key; VersionId; IsLatest; IsDeleteMarker; LastModified; Size }.
    .DESCRIPTION
        Azure has no native delete markers: CIPP's own deletes show as a marker version, other deletes only as versions
        with IsLatest $false. S3 reports objects written before versioning was enabled with VersionId 'null'.
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
        'AzureBlob' { Get-CIPPCloudBackupAzureObjectVersionList @PSBoundParameters }
        'S3' { Get-CIPPCloudBackupS3ObjectVersionList @PSBoundParameters }
        default { throw [System.ArgumentException]::new("Unknown cloud backup provider '$($Destination.Provider)'.") }
    }
}
