function Get-CIPPJITAdminCloudError {
    <#
    .SYNOPSIS
        Returns why JIT Admin cannot run for a government tenant, or nothing.
    .DESCRIPTION
        JIT Admin uses the cippUser schema extension, which exists only in the partner's cloud. Refuses a
        tenant in another cloud even when the support matrix cannot be read. Never logs.
    .PARAMETER TenantFilter
        The tenant's default domain name or id.
    .PARAMETER CloudEnvironment
        The tenant's cloud, when already known.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$TenantFilter,
        [string]$CloudEnvironment
    )

    if (-not $CloudEnvironment) {
        if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -in @('AllTenants', 'allTenants', 'PartnerTenant')) { return }
        $CloudEnvironment = try { Get-CIPPTenantRequestCloud -TenantFilter $TenantFilter } catch { $null }
    }
    if ([string]::IsNullOrEmpty($CloudEnvironment) -or $CloudEnvironment -ceq 'Commercial') { return }
    $PartnerCloud = try { Get-CIPPPartnerCloudEnvironment } catch { 'Commercial' }
    if ($CloudEnvironment -ceq $PartnerCloud) { return }

    $Entry = try { Get-CIPPCloudFeatureSupport -Type 'pages' -Name '/identity/administration/jit-admin' -CloudEnvironment $CloudEnvironment } catch { $null }
    $Reason = if ($Entry.Reason) { $Entry.Reason } else { "JIT Admin stores its state in CIPP's cippUser schema extension, which exists only in the partner tenant's cloud." }
    return "JIT Admin is not supported for $CloudEnvironment tenants. $Reason"
}
