function Get-CIPPJITAdminCloudError {
    <#
    .SYNOPSIS
        Returns why JIT Admin cannot run for a government tenant, or nothing.
    .DESCRIPTION
        JIT Admin keeps its state in the cippUser schema extension that Get-CIPPSchemaExtensions reads
        and creates in the partner tenant, with CIPP-SAM, in the partner's cloud. A GCC High or DoD direct
        tenant of a commercial partner is in another cloud, where that extension does not exist, so every
        JIT Admin read or write fails there (500 Resource 'ext..._cippUser' does not exist). JIT paths call
        this before Get-CIPPSchemaExtensions and stop when it returns a message (redanthrax/CIPP#4).
        A government tenant in the partner's own cloud (CIPP_PARTNER_CLOUD) shares the extension and is
        not refused.

        Returns nothing for Commercial tenants, the partner tenant, AllTenants, an empty filter and a
        tenant whose cloud cannot be resolved, so those callers run exactly as before. Unlike
        Test-CIPPCloudFeatureSupport it refuses a government cloud other than the partner's even when the
        support matrix cannot be read (the matrix only supplies the reason text). Never logs.
    .PARAMETER TenantFilter
        The tenant's default domain name or id.
    .PARAMETER CloudEnvironment
        The tenant's cloud, when already known.
    .OUTPUTS
        [string] The message, or nothing.
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
