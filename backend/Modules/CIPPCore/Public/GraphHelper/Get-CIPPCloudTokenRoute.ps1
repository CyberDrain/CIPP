function Get-CIPPCloudTokenRoute {
    <#
    .SYNOPSIS
        Decides the authority, app and scope Get-GraphToken uses for a tenant outside the commercial path.
    .DESCRIPTION
        Get-GraphToken only calls this when the tenant's cloud or the partner cloud is not
        Commercial; commercial tenants on a commercial instance never reach it. The choice comes
        from fixed tables only (redanthrax/CIPP#2):

          - authority and Graph host: Get-CIPPCloudEndpoint for the tenant's cloud (throws for an
            unknown, empty or miscased value)
          - scope: ConvertTo-CIPPCloudScope (throws for a non-Graph resource on a government tenant)
          - app: CIPP's SAM app when the tenant is in the partner cloud (where that app is
            registered); the Azure Government app for a government tenant on an instance in
            another cloud. A missing Azure Government app throws - it never falls back to the SAM
            app's credentials. A commercial tenant on a government instance is not supported.

        The government app authenticates with its certificate when certificate authentication is on
        or no client secret is stored (the same rule as the SAM app), and with its secret otherwise.
    .PARAMETER CloudEnvironment
        The tenant's cloud.
    .PARAMETER Scope
        The scope the caller asked for (commercial form).
    .PARAMETER CachedOnly
        Return $null instead of reading storage when the government app credentials are not loaded
        in this process yet (used by the token cache fast path).
    .OUTPUTS
        PSCustomObject: CloudEnvironment, Authority, Scope, UsesGovApp, ClientId, UseCertificate,
        CertificateName. Holds no secret.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$CloudEnvironment,
        [Parameter(Mandatory = $true)]
        [string]$Scope,
        [switch]$CachedOnly
    )

    $Endpoint = Get-CIPPCloudEndpoint -CloudEnvironment $CloudEnvironment
    $PartnerCloud = Get-CIPPPartnerCloudEnvironment
    $CloudScope = ConvertTo-CIPPCloudScope -Scope $Scope -CloudEnvironment $Endpoint.CloudEnvironment

    if ($Endpoint.CloudEnvironment -ceq $PartnerCloud) {
        return [pscustomobject]@{
            CloudEnvironment = $Endpoint.CloudEnvironment
            Authority        = $Endpoint.Authority
            Scope            = $CloudScope
            UsesGovApp       = $false
            ClientId         = [string]$env:ApplicationID
            UseCertificate   = [bool]$env:CertificateAuthMode
            CertificateName  = 'SAMCertificate'
        }
    }

    if (-not $Endpoint.IsGovernment) {
        throw "This CIPP instance runs in the $PartnerCloud cloud (CIPP_PARTNER_CLOUD); tokens for a $($Endpoint.CloudEnvironment) tenant are not supported."
    }

    if ($CachedOnly -and $env:CIPPGovAppLoaded -ne 'true') { return $null }

    $Gov = Get-CIPPGovAppCredential
    if (-not $Gov.Configured) {
        throw 'Azure Government app not configured. Add the application id and a client secret or certificate of the Azure Government app registration under CIPP > Advanced > Authentication > Credentials to manage GCC High and DoD tenants.'
    }
    $UseCertificate = [bool]$env:CertificateAuthMode -or -not $Gov.HasSecret
    if ($UseCertificate -and -not $Gov.HasCertificate) {
        throw 'Certificate authentication is enabled but the Azure Government app has no certificate. Generate one under CIPP > Advanced > Authentication > Credentials and upload it to the app registration.'
    }
    return [pscustomobject]@{
        CloudEnvironment = $Endpoint.CloudEnvironment
        Authority        = $Endpoint.Authority
        Scope            = $CloudScope
        UsesGovApp       = $true
        ClientId         = $Gov.ApplicationId
        UseCertificate   = $UseCertificate
        CertificateName  = 'GovSAMCertificate'
    }
}
