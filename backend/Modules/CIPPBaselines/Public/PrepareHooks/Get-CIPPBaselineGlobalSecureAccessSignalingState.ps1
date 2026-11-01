function Get-CIPPBaselineGlobalSecureAccessSignalingState {
    <#
    .SYNOPSIS
        Prepare hook for GlobalSecureAccessSignaling: grades the Conditional Access
        signaling setting from the NetworkAccess cache.
    .DESCRIPTION
        Every networkAccess path except tenantStatus answers 403 until the tenant is
        onboarded, so the cache collector records no signaling status for a tenant that
        is not onboarded, and the declarative PATCH would fail against Graph's ambiguous
        403 (missing app permission or missing onboarding?). Such a tenant is not graded
        here: the hook names the onboarding prerequisite and the engine reports it as an
        error until "Onboard Global Secure Access" has run.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $State = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'NetworkAccess' | Where-Object { $_ }) | Select-Object -First 1
    if (-not $State) { return @{ Current = $null } }
    if ($State.onboarded -ne $true) {
        return @{
            Current      = $null
            NoDataReason = 'the tenant is not onboarded to Global Secure Access - enable the "Onboard Global Secure Access" standard first'
        }
    }
    @{ Current = $State }
}
