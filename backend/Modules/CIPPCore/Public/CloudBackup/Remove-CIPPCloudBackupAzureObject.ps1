function Remove-CIPPCloudBackupAzureObject {
    <#
    .SYNOPSIS
        Deletes a blob and its snapshots, or one version of it, from an Azure Blob cloud backup destination. A missing blob or version is not an error.
    .DESCRIPTION
        Without -VersionId the blob first gets a cippdeletedat metadata version, so on a versioned account the deletion
        time is kept (as a delete marker for Get-CIPPCloudBackupObjectVersionList and Remove-CIPPCloudBackupExpiredVersion).
        On a destination with ImmutabilityDays the marker is an empty upload that stays the current version instead, because
        version-level immutability refuses Set Blob Metadata and Delete Blob on a protected version but allows an overwrite.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [string]$VersionId
    )

    if (-not $PSCmdlet.ShouldProcess($Key, 'Delete')) { return }

    if ($VersionId) {
        $Response = Invoke-CIPPCloudBackupAzureBlobRequest -Destination $Destination -Method 'DELETE' -Key $Key -Query ([ordered]@{ versionid = $VersionId }) -AllowStatus 403, 404
        if ($Response.StatusCode -eq 403) {
            $Exception = [System.Exception]::new("Azure Storage refused to delete version $VersionId of '$Key' ($($Response.ErrorCode)): CIPP's app needs the Storage Blob Data Owner role on the storage account to remove old versions.")
            $Exception.Data['StatusCode'] = 403
            throw $Exception
        }
        return
    }

    if (($Destination.ImmutabilityDays -as [int]) -gt 0) {
        $Current = Invoke-CIPPCloudBackupAzureBlobRequest -Destination $Destination -Method 'HEAD' -Key $Key -AllowStatus 404
        if ($Current.StatusCode -eq 404 -or $Current.Headers['x-ms-meta-cippdeletedat']) { return }
        $null = Invoke-CIPPCloudBackupAzureBlobRequest -Destination $Destination -Method 'PUT' -Key $Key -Body ([byte[]]::new(0)) -Headers @{ 'x-ms-blob-type' = 'BlockBlob'; 'x-ms-meta-cippdeletedat' = [datetime]::UtcNow.ToString('o') }
        return
    }

    $Marker = Invoke-CIPPCloudBackupAzureBlobRequest -Destination $Destination -Method 'PUT' -Key $Key -Query ([ordered]@{ comp = 'metadata' }) -Headers @{ 'x-ms-meta-cippdeletedat' = [datetime]::UtcNow.ToString('o') } -AllowStatus 404
    if ($Marker.StatusCode -eq 404) { return }
    $null = Invoke-CIPPCloudBackupAzureBlobRequest -Destination $Destination -Method 'DELETE' -Key $Key -Headers @{ 'x-ms-delete-snapshots' = 'include' } -AllowStatus 404
}
