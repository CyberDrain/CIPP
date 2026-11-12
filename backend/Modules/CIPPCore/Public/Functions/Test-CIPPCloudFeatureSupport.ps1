function Test-CIPPCloudFeatureSupport {
    <#
    .SYNOPSIS
        Tests whether a tenant's Microsoft cloud supports a feature.
    .DESCRIPTION
        The cloud counterpart of Test-CIPPStandardLicense (redanthrax/CIPP#4): background jobs ask it
        before running a standard, alert, test, cache type or timer step for a tenant, and skip the
        work when it returns $false - with one informational log line per run and tenant, written by
        the caller - instead of failing on the government refusal from #3.

        Returns $true for Commercial tenants, the partner tenant, AllTenants and an empty filter. The
        tenant's cloud comes from Get-CIPPTenantRequestCloud, the rule the request helpers route by.
        If the cloud cannot be resolved the answer is $true, so the caller behaves exactly as before
        and the request helpers decide (they refuse an unknown cloud themselves).

        Never logs. -CloudEnvironment skips the lookup when the caller already knows the cloud (for
        example from Get-Tenants in a fan-out).
    .PARAMETER TenantFilter
        The tenant's default domain name or id.
    .PARAMETER Type
        The support-matrix section (see Get-CIPPCloudFeatureSupport).
    .PARAMETER Name
        The feature's key in that section.
    .PARAMETER CloudEnvironment
        The tenant's cloud, when already known.
    .OUTPUTS
        [bool]
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [ValidateSet('pages', 'actions', 'standards', 'baselineStandards', 'alerts', 'tests', 'cacheTypes', 'timers')]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$CloudEnvironment
    )

    if (-not $CloudEnvironment) {
        if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -in @('AllTenants', 'allTenants', 'PartnerTenant')) { return $true }
        $CloudEnvironment = try { Get-CIPPTenantRequestCloud -TenantFilter $TenantFilter } catch { $null }
    }
    if ([string]::IsNullOrEmpty($CloudEnvironment) -or $CloudEnvironment -ceq 'Commercial') { return $true }

    return -not (Get-CIPPCloudFeatureSupport -Type $Type -Name $Name -CloudEnvironment $CloudEnvironment)
}
