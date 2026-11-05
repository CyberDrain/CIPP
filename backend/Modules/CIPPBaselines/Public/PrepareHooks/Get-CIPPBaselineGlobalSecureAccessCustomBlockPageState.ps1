function Get-CIPPBaselineGlobalSecureAccessCustomBlockPageState {
    <#
    .SYNOPSIS
        Prepare hook for GlobalSecureAccessCustomBlockPage: grades the custom block page
        from the LIVE settings.
    .DESCRIPTION
        The block page is a singleton setting administrators deliberately edit, so the
        verdict must be the tenant's actual state - the same reasoning as the signaling
        standard. The hook reads the live tenant status first (onboarding gate, the
        prerequisite named clearly) then the live custom block page: state and markdown
        message. The expected state is conditional - disabled grades the state alone,
        because Microsoft's default block page is used and the message expresses no
        opinion. An enabled page with no configured message is a configuration error.
        Remediation is fully declarative through the documented settings PATCH, so this
        hook is the only custom code.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $V = $Item.Variables
    if ($V -is [System.Collections.IDictionary]) { $V = [PSCustomObject]$V }
    $State = "$($V.state)"
    if (-not $State) { $State = 'enabled' }
    $Message = "$($V.blockMessage)"

    if ($State -notin @('enabled', 'disabled')) {
        return @{ Current = $null; ConfigError = $true; NoDataReason = "state must be 'enabled' or 'disabled', not '$State'." }
    }
    if ($State -eq 'enabled' -and -not $Message) {
        return @{ Current = $null; ConfigError = $true; NoDataReason = 'the custom block page is enabled but no message is configured - a block page with an empty message shows users nothing.' }
    }

    $Graph = 'https://graph.microsoft.com/beta'
    try {
        $Status = New-GraphGetRequest -uri "$Graph/networkAccess/tenantStatus" -tenantid $TenantFilter -AsApp $true
    } catch {
        return @{ Current = $null; NoDataReason = "could not read the Global Secure Access tenant status: $($_.Exception.Message)" }
    }
    if ($Status.onboardingStatus -ne 'onboarded') {
        return @{ Current = $null; NoDataReason = 'the tenant is not onboarded to Global Secure Access - enable the "Onboard Global Secure Access" standard first' }
    }
    try {
        $Page = New-GraphGetRequest -uri "$Graph/networkAccess/settings/customBlockPage" -tenantid $TenantFilter -AsApp $true
    } catch {
        return @{ Current = $null; NoDataReason = "could not read the Global Secure Access custom block page: $($_.Exception.Message)" }
    }

    $Current = [ordered]@{
        state        = "$($Page.state)"
        blockMessage = "$($Page.configuration.body)"
    }
    $Expected = [ordered]@{
        state = $State
    }
    if ($State -eq 'enabled') { $Expected.blockMessage = $Message }
    @{ Expected = [PSCustomObject]$Expected; Current = [PSCustomObject]$Current }
}
