function Set-CIPPDBCacheOrganization {
    <#
    .SYNOPSIS
        Caches organization information for a tenant

    .PARAMETER TenantFilter
        The tenant to cache organization data for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    .NOTES
        Permission: Graph | GET /organization | Delegated | DeviceManagementServiceConfig.Read.All | Organization.Read.All, Directory.Read.All, Organization.ReadWrite.All, Directory.ReadWrite.All
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching organization data' -sev Debug

        New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/organization' -tenantid $TenantFilter -Stream |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Organization' -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached organization data successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter `
            -message "Failed to cache organization data: $($_.Exception.Message)" -sev Error
    }
}
