function Get-CIPPBaselineGlobalSecureAccessInternetProfileState {
    <#
    .SYNOPSIS
        Prepare hook for GlobalSecureAccessInternetProfile.
    .DESCRIPTION
        Thin wrapper: the shared forwarding-profile grading core with the Internet
        traffic type. See Get-CIPPBaselineForwardingProfileState for the assignment
        model and grading rules.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    Get-CIPPBaselineForwardingProfileState -Item $Item -TenantFilter $TenantFilter -TrafficType 'internet' -ProfileLabel 'Internet'
}
