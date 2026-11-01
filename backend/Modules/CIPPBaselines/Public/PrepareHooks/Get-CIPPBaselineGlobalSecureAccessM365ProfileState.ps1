function Get-CIPPBaselineGlobalSecureAccessM365ProfileState {
    <#
    .SYNOPSIS
        Prepare hook for GlobalSecureAccessM365Profile.
    .DESCRIPTION
        Thin wrapper: the shared forwarding-profile grading core with the Microsoft 365
        traffic type. See Get-CIPPBaselineForwardingProfileState for the assignment
        model and grading rules.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    Get-CIPPBaselineForwardingProfileState -Item $Item -TenantFilter $TenantFilter -TrafficType 'm365' -ProfileLabel 'Microsoft 365'
}
