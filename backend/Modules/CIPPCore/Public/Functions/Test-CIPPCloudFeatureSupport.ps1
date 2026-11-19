function Test-CIPPCloudFeatureSupport {
    <#
    .SYNOPSIS
        Tests whether a tenant's Microsoft cloud supports a feature.
    .DESCRIPTION
        Cloud counterpart of Test-CIPPStandardLicense. Returns $true for Commercial, the partner tenant,
        AllTenants, an empty filter and an unresolvable cloud. Never logs.
    .PARAMETER TenantFilter
        The tenant's default domain name or id.
    .PARAMETER Type
        The support-matrix section (see Get-CIPPCloudFeatureSupport).
    .PARAMETER Name
        The feature's key in that section.
    .PARAMETER CloudEnvironment
        The tenant's cloud, when already known.
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
