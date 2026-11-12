function Get-CIPPPartnerCloudEnvironment {
    <#
    .SYNOPSIS
        Returns the Microsoft cloud this CIPP instance's partner tenant (and SAM app) lives in.
    .DESCRIPTION
        Read from the CIPP_PARTNER_CLOUD app setting; unset means Commercial. Any value other than
        Commercial, USGovHigh or USGovDoD (exact case) throws.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Value = $env:CIPP_PARTNER_CLOUD
    if ([string]::IsNullOrEmpty($Value)) { return 'Commercial' }
    foreach ($Allowed in 'Commercial', 'USGovHigh', 'USGovDoD') {
        if ($Value -ceq $Allowed) { return $Allowed }
    }
    throw 'The CIPP_PARTNER_CLOUD application setting is not valid. Set it to exactly Commercial, USGovHigh or USGovDoD, or remove it to use Commercial.'
}
