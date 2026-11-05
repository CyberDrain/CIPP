function Invoke-CIPPBaselineGlobalSecureAccessInternetProfile {
    <#
    .SYNOPSIS
        GlobalSecureAccessInternetProfile executor.
    .DESCRIPTION
        Thin wrapper: the shared forwarding-profile remediation core with the Internet
        traffic type. See Invoke-CIPPBaselineForwardingProfile for the write model.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Remediate, $TenantFilter, $Current)

    Invoke-CIPPBaselineForwardingProfile -Remediate $Remediate -TenantFilter $TenantFilter -Current $Current -TrafficType 'internet' -ProfileLabel 'Internet'
}
