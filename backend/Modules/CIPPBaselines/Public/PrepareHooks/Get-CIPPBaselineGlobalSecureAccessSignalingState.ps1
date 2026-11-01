function Get-CIPPBaselineGlobalSecureAccessSignalingState {
    <#
    .SYNOPSIS
        Prepare hook for GlobalSecureAccessSignaling: grades the LIVE Conditional Access
        signaling setting.
    .DESCRIPTION
        Signaling is a single toggle administrators flip deliberately (to test drift, or
        to park source IP restoration), so the verdict must be the tenant's actual state:
        reading the NetworkAccess cache would grade whatever the last scheduled collection
        saw, and a toggle flipped in between reports compliant for a tenant that is not.
        The hook reads the live tenant status first - every networkAccess path except
        tenantStatus answers 403 until the tenant is onboarded, so a tenant that is not
        onboarded gets the prerequisite named clearly instead of Graph's ambiguous 403
        (missing app permission or missing onboarding?) - then the live signaling setting.
        A failed live read reports No Data with the reason rather than grading a stale
        value.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $Graph = 'https://graph.microsoft.com/beta'
    try {
        $Status = New-GraphGetRequest -uri "$Graph/networkAccess/tenantStatus" -tenantid $TenantFilter -AsApp $true
    } catch {
        return @{ Current = $null; NoDataReason = "could not read the Global Secure Access tenant status: $($_.Exception.Message)" }
    }
    if ($Status.onboardingStatus -ne 'onboarded') {
        return @{
            Current      = $null
            NoDataReason = 'the tenant is not onboarded to Global Secure Access - enable the "Onboard Global Secure Access" standard first'
        }
    }
    try {
        $Settings = New-GraphGetRequest -uri "$Graph/networkAccess/settings/conditionalAccess" -tenantid $TenantFilter -AsApp $true
    } catch {
        return @{ Current = $null; NoDataReason = "could not read the Global Secure Access signaling setting: $($_.Exception.Message)" }
    }
    @{ Current = [PSCustomObject]@{ signalingStatus = $Settings.signalingStatus } }
}
