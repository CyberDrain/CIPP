function Get-CIPPIntuneDeployableType {
    <#
    .SYNOPSIS
        The Intune template types Set-CIPPIntunePolicy knows how to deploy.

    .DESCRIPTION
        Set-CIPPIntunePolicy dispatches on template type through a switch. A type the switch does not
        name is not deployable: nothing is sent to Graph and, because the switch has no fallthrough of
        its own, the caller cannot tell that from a successful deployment. Every path that stores or
        deploys a template checks against this list so an undeployable type is refused at the point it
        is introduced rather than discovered on a tenant.

        This list and the switch have to agree. Set-CIPPIntunePolicy.Tests.ps1 reads the switch labels
        back out of the source with the AST and fails if they diverge, so adding a branch there
        without adding it here - or the reverse - is caught in CI rather than in production.

    .EXAMPLE
        if ($Type -notin (Get-CIPPIntuneDeployableType)) { throw 'Not deployable' }
    #>
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    return @(
        'AppProtection'
        'AppConfiguration'
        'deviceCompliancePolicies'
        'Admin'
        'Device'
        'Catalog'
        'windowsDriverUpdateProfiles'
        'windowsFeatureUpdateProfiles'
        'windowsQualityUpdatePolicies'
        'windowsQualityUpdateProfiles'
    )
}
