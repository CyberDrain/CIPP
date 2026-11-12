function Get-CIPPPartnerCloudEnvironment {
    <#
    .SYNOPSIS
        Returns the Microsoft cloud this CIPP instance's partner tenant (and SAM app) lives in.
    .DESCRIPTION
        GDAP does not work across clouds, so the partner tenant, every GDAP tenant and CIPP's own
        SAM application are always in the same cloud. That cloud is an instance-level setting read
        from the CIPP_PARTNER_CLOUD application setting (environment variable):

            unset or empty  Commercial (the default, and the behaviour before redanthrax/CIPP#2)
            Commercial      commercial / GCC Moderate partner
            USGovHigh       GCC High partner
            USGovDoD        DoD partner

        The value must match exactly (case-sensitive). Anything else throws rather than being read
        as Commercial: a mistyped setting must stop token requests, not send them to the wrong cloud.

        Set it in the Function App's Configuration > Application settings (or local.settings.json
        when developing) and restart the app.
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
