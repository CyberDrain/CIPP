function Get-CIPPCloudBackupAzureVersioning {
    <#
    .SYNOPSIS
        Returns 'Enabled' or 'Disabled' for blob versioning on the storage account of an Azure Blob cloud backup destination.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination
    )

    $Service = Invoke-CIPPCloudBackupAzureManagementRequest -Destination $Destination -Method 'GET' -Path 'blobServices/default'
    if ($Service.properties.isVersioningEnabled -eq $true) { return 'Enabled' }
    return 'Disabled'
}
