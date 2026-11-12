function Get-CIPPTenantRequestCloud {
    <#
    .SYNOPSIS
        Returns the cloud whose API hosts a request for a tenant must use.
    .DESCRIPTION
        Used by the request helpers (New-GraphGetRequest and friends, redanthrax/CIPP#3) to choose
        hosts with the same rule Get-GraphToken uses to choose the authority and app (#2): a direct
        tenant's stored cloudEnvironment, otherwise the partner cloud (CIPP_PARTNER_CLOUD).

        Hot path: one in-memory lookup of the cloud marker Get-GraphToken leaves in the shared
        token cache (CIPP.CIPPTokenCache, 15 minutes). Only on a miss is the Tenants table read,
        and the answer is stored under the same marker. So the host and the token for a request
        always follow the same marker and cannot disagree about the cloud.

        Throws for an unknown, empty or miscased stored value and for a bad CIPP_PARTNER_CLOUD
        (Get-CIPPCloudEndpoint, Get-CIPPPartnerCloudEnvironment). Never falls back to Commercial.
    .PARAMETER TenantFilter
        The tenant id or domain as passed to the request helper (empty = the partner tenant).
    .OUTPUTS
        Commercial, USGovHigh or USGovDoD.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$TenantFilter
    )

    # Trimmed like the cache key (CIPPTokenCache.BuildKey trims), so ' <id>' cannot share a tenant's marker
    # while missing its Tenants row and overwrite that marker with the partner cloud (redanthrax/CIPP#3).
    $TenantId = if ([string]::IsNullOrEmpty($TenantFilter)) { [string]$env:TenantID } else { $TenantFilter.Trim() }
    $MarkerKey = $null
    if ($null -ne ('CIPP.CIPPTokenCache' -as [type])) {
        $MarkerKey = [CIPP.CIPPTokenCache]::BuildKey($TenantId, 'cipp-cloud-environment', $false, '', 'marker')
        $Marker = [CIPP.CIPPTokenCache]::Lookup($MarkerKey, 0)
        if ($Marker.Found -and $Marker.TokenPayloadJson) {
            if ($Marker.TokenPayloadJson -ceq 'Commercial') { return 'Commercial' }
            return (Get-CIPPCloudEndpoint -CloudEnvironment $Marker.TokenPayloadJson).CloudEnvironment
        }
    }

    # Same lookup as Get-GraphToken: direct tenants by customerId or defaultDomainName, then a government
    # (non-Commercial) direct tenant by initialDomainName.
    $Cloud = Get-CIPPPartnerCloudEnvironment
    if ($TenantId -ne $env:TenantID) {
        $TenantsTable = Get-CippTable -tablename 'Tenants'
        $DirectTenantRows = Get-CIPPAzDataTableEntity @TenantsTable -Filter "PartitionKey eq 'Tenants' and delegatedPrivilegeStatus eq 'directTenant'"
        $DirectTenant = $DirectTenantRows | Where-Object { $_.customerId -eq $TenantId -or $_.defaultDomainName -eq $TenantId } | Select-Object -First 1
        if (-not $DirectTenant) { $DirectTenant = $DirectTenantRows | Where-Object { $_.initialDomainName -and $_.initialDomainName -eq $TenantId -and $_.cloudEnvironment -and $_.cloudEnvironment -cne 'Commercial' } | Select-Object -First 1 }
        $StoredCloud = [string]$DirectTenant.cloudEnvironment
        if ($DirectTenant -and -not [string]::IsNullOrEmpty($StoredCloud)) { $Cloud = $StoredCloud }
    }
    $Cloud = (Get-CIPPCloudEndpoint -CloudEnvironment $Cloud).CloudEnvironment

    if ($MarkerKey) {
        # Same rule as Get-GraphToken: the first time this worker sees the tenant in a government cloud, drop
        # its cached tokens, which may be commercial ones minted before the cloud changed in another worker.
        # Commercial answers do nothing here: Get-GraphToken clears the 'seen' entry when it mints a commercial token.
        if ($Cloud -cne 'Commercial') {
            $SeenKey = [CIPP.CIPPTokenCache]::BuildKey($TenantId, 'cipp-cloud-environment', $false, '', 'seen')
            $Seen = [CIPP.CIPPTokenCache]::Lookup($SeenKey, 0)
            if (-not ($Seen.Found -and $Seen.TokenPayloadJson -ceq $Cloud)) { $null = [CIPP.CIPPTokenCache]::RemoveByTenant($TenantId) }
            [CIPP.CIPPTokenCache]::Store($SeenKey, $Cloud, [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 86400)
        }
        [CIPP.CIPPTokenCache]::Store($MarkerKey, $Cloud, [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 900)
    }
    return $Cloud
}
