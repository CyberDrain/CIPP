function Invoke-CIPPBaselineGlobalSecureAccessM365Profile {
    <#
    .SYNOPSIS
        GlobalSecureAccessM365Profile executor.
    .DESCRIPTION
        Thin wrapper: the shared forwarding-profile remediation core with the Microsoft
        365 traffic type. See Invoke-CIPPBaselineForwardingProfile for the write model.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Remediate, $TenantFilter, $Current)

    Invoke-CIPPBaselineForwardingProfile -Remediate $Remediate -TenantFilter $TenantFilter -Current $Current -TrafficType 'm365' -ProfileLabel 'Microsoft 365'
}
