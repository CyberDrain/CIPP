function Get-CIPPTenantCloudEnvironment {
    <#
    .SYNOPSIS
        Works out which Microsoft cloud a tenant lives in: Commercial, USGovHigh or USGovDoD.
    .DESCRIPTION
        Uses the tenant's OpenID discovery document, falling back to the initial domain (*.onmicrosoft.us
        is USGovHigh; that fallback cannot detect DoD). GCC Moderate is Commercial. Never throws.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$TenantId,
        # Used when discovery is unavailable
        [string]$InitialDomainName
    )

    # \z, not $: .NET's $ also matches before a trailing newline, which would let "id`n" validate.
    $GuidPattern = '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z'
    $DomainPattern = '^(?=.{1,253}\z)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+[A-Za-z]{2,63}\z'

    $FromDomain = if ($InitialDomainName -match $DomainPattern -and $InitialDomainName -match '\.onmicrosoft\.us\z') { 'USGovHigh' } else { 'Commercial' }

    if ([string]::IsNullOrWhiteSpace($TenantId) -or ($TenantId -notmatch $GuidPattern -and $TenantId -notmatch $DomainPattern)) {
        # Logging can fail; that must not throw here.
        try { Write-LogMessage -API 'CloudEnvironment' -tenant $InitialDomainName -message "Cannot detect the cloud environment from tenant id '$TenantId' as it is not a GUID or domain. Using $FromDomain based on the initial domain." -Sev 'Warning' } catch {}
        return $FromDomain
    }

    try {
        $Uri = 'https://login.microsoftonline.com/{0}/v2.0/.well-known/openid-configuration' -f [uri]::EscapeDataString($TenantId)
        $Discovery = Invoke-RestMethod -Uri $Uri -Method GET -TimeoutSec 15 -ErrorAction Stop

        $IsUSGov = $Discovery.cloud_instance_name -eq 'microsoftonline.us' -or $Discovery.tenant_region_scope -eq 'USGov'
        if ($IsUSGov) {
            if ($Discovery.tenant_region_sub_scope -eq 'DOD') { return 'USGovDoD' }
            return 'USGovHigh'
        }
        # Discovery says commercial, but an onmicrosoft.us initial domain can only be a gov tenant.
        return $FromDomain
    } catch {
        try { Write-LogMessage -API 'CloudEnvironment' -tenant $InitialDomainName -tenantid $TenantId -message "Could not read OpenID discovery for tenant $TenantId to detect its cloud environment, using $FromDomain based on the initial domain: $($_.Exception.Message)" -Sev 'Warning' } catch {}
        return $FromDomain
    }
}
