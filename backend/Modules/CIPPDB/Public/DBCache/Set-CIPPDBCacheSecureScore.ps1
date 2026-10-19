function Set-CIPPDBCacheSecureScore {
    <#
    .SYNOPSIS
        Caches secure score history (last 14 days) and control profiles for a tenant

    .PARAMETER TenantFilter
        The tenant to cache secure score for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    .NOTES
        Permission: Graph | GET /security/secureScoreControlProfiles | Delegated | SecurityEvents.Read.All | SecurityEvents.ReadWrite.All
        Permission: Graph | GET /security/secureScores | Delegated | SecurityEvents.Read.All | SecurityEvents.ReadWrite.All
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching secure score' -sev Debug

        # Cache secure score history (last 14 days)
        $SecureScore = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/secureScores?$top=14' -tenantid $TenantFilter -noPagination $true
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SecureScore' -Data $SecureScore -AddCount

        # Cache secure score control profiles
        $Profiles = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/security/secureScoreControlProfiles' -tenantid $TenantFilter
        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'SecureScoreControlProfiles' -Data $Profiles -AddCount

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached secure score and control profiles successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache secure score: $($_.Exception.Message)" -sev Error
    }
}
