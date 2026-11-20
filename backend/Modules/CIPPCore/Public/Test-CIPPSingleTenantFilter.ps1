function Test-CIPPSingleTenantFilter {
    <#
    .SYNOPSIS
        Returns true when a tenantFilter names one tenant, not AllTenants or a tenant group.
    .PARAMETER TenantFilter
        The tenantFilter value to check.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [string]$TenantFilter
    )

    -not ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants' -or $TenantFilter -like 'group:*')
}
