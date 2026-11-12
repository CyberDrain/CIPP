function Get-CIPPTenantRequestCloud {
    <#
    .SYNOPSIS
        Returns the cloud whose API hosts a request for a tenant must use.
    .DESCRIPTION
        Same rule as Get-GraphToken and the same cached cloud marker, so a request's host and token
        always agree. Never falls back to Commercial.
    .PARAMETER TenantFilter
        The tenant id or domain as passed to the request helper (empty = the partner tenant).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$TenantFilter
    )

    # Trim like CIPPTokenCache.BuildKey so ' <id>' can't overwrite the tenant's marker.
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

    # Keep in sync with Get-GraphToken's tenant lookup.
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
        # First time this worker sees the tenant in a gov cloud, drop tokens possibly minted for the old cloud.
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
