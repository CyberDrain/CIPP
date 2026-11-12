function Get-CIPPCloudEndpoint {
    <#
    .SYNOPSIS
        Returns the fixed identity and API hosts for a Microsoft cloud.
    .DESCRIPTION
        The single source of truth for which hosts CIPP talks to for a tenant's cloudEnvironment
        (redanthrax/CIPP#2, #3). Keyed on the three canonical values only:

            Commercial  login.microsoftonline.com  graph.microsoft.com      (also GCC Moderate)
            USGovHigh   login.microsoftonline.us   graph.microsoft.us
            USGovDoD    login.microsoftonline.us   dod-graph.microsoft.us

        The match is exact and case-sensitive. Anything else - empty, null, 'usgovhigh', a host
        name - throws, so an unexpected stored value can never fall back to commercial hosts or
        credentials. Every value below is a literal: no host is ever built from a stored value,
        a discovery document or request input.

        API hosts per cloud (redanthrax/CIPP#3). A service with no documented government host is left
        out on purpose (Teams admin ConfigAPI, Security & Compliance PowerShell, Partner Center, the
        classic admin.microsoft.com APIs, ...): Resolve-CIPPCloudHost refuses it for a government
        tenant rather than guess.

            Service     Commercial                        USGovHigh                           USGovDoD
            Graph       graph.microsoft.com               graph.microsoft.us                  dod-graph.microsoft.us
            Exchange    outlook.office365.com             outlook.office365.us                webmail.apps.mil
            Management  manage.office.com                 manage.office365.us                 manage.protection.apps.mil
            Defender    api.securitycenter.microsoft.com  api-gov.securitycenter.microsoft.us api-gov.securitycenter.microsoft.us
            SharePoint  *.sharepoint.com                  *.sharepoint.us                     *.sharepoint-mil.us

        Sources (each host is quoted from these pages):
            Graph       https://learn.microsoft.com/graph/deployments
            Exchange    https://learn.microsoft.com/powershell/module/exchangepowershell/connect-exchangeonline (ConnectionUri)
            Management  https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-reference
            Defender    https://learn.microsoft.com/defender-endpoint/gov (API section)
            SharePoint  https://learn.microsoft.com/microsoft-365/enterprise/microsoft-365-u-s-government-gcc-high-endpoints
                        https://learn.microsoft.com/microsoft-365/enterprise/microsoft-365-u-s-government-dod-endpoints

        The token resource of each service is https://<host>, as for commercial. Microsoft documents
        the government hosts but not, for Exchange, Management and Defender, the government token
        resource in so many words; a wrong one fails at the government authority (AADSTS500011), never
        at a commercial host.

        To add a service, add a literal host to every entry's ServiceHosts.
    .PARAMETER CloudEnvironment
        Commercial, USGovHigh or USGovDoD (exact case).
    .OUTPUTS
        PSCustomObject with CloudEnvironment, IsGovernment, LoginHost, Authority, GraphHost, GraphUrl,
        GraphScope, ExchangeHost, ManagementHost, DefenderHost, SharePointSuffix and ServiceHosts (a
        read-only map of service name - Graph, Exchange, Management, Defender - to that cloud's host).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$CloudEnvironment
    )

    if (-not $script:CIPPCloudEndpointMap) {
        # Ordinal comparer: 'usgovhigh' must not resolve to 'USGovHigh'.
        $Map = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        # Read-only, so a caller cannot change a host for everyone through the shallow copy below.
        function New-ServiceHosts([string]$Graph, [string]$Exchange, [string]$Management, [string]$Defender) {
            $Hosts = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
            $Hosts['Graph'] = $Graph
            $Hosts['Exchange'] = $Exchange
            $Hosts['Management'] = $Management
            $Hosts['Defender'] = $Defender
            , [System.Collections.ObjectModel.ReadOnlyDictionary[string, string]]::new($Hosts)
        }
        $Map['Commercial'] = [pscustomobject]@{
            CloudEnvironment = 'Commercial'
            IsGovernment     = $false
            LoginHost        = 'login.microsoftonline.com'
            Authority        = 'https://login.microsoftonline.com'
            GraphHost        = 'graph.microsoft.com'
            GraphUrl         = 'https://graph.microsoft.com'
            GraphScope       = 'https://graph.microsoft.com/.default'
            ExchangeHost     = 'outlook.office365.com'
            ManagementHost   = 'manage.office.com'
            DefenderHost     = 'api.securitycenter.microsoft.com'
            SharePointSuffix = 'sharepoint.com'
            ServiceHosts     = (New-ServiceHosts 'graph.microsoft.com' 'outlook.office365.com' 'manage.office.com' 'api.securitycenter.microsoft.com')
        }
        $Map['USGovHigh'] = [pscustomobject]@{
            CloudEnvironment = 'USGovHigh'
            IsGovernment     = $true
            LoginHost        = 'login.microsoftonline.us'
            Authority        = 'https://login.microsoftonline.us'
            GraphHost        = 'graph.microsoft.us'   # https://learn.microsoft.com/graph/deployments
            GraphUrl         = 'https://graph.microsoft.us'
            GraphScope       = 'https://graph.microsoft.us/.default'
            ExchangeHost     = 'outlook.office365.us'   # https://learn.microsoft.com/powershell/module/exchangepowershell/connect-exchangeonline
            ManagementHost   = 'manage.office365.us'   # https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-reference
            DefenderHost     = 'api-gov.securitycenter.microsoft.us'   # https://learn.microsoft.com/defender-endpoint/gov (GCC High and DoD share it)
            SharePointSuffix = 'sharepoint.us'   # https://learn.microsoft.com/microsoft-365/enterprise/microsoft-365-u-s-government-gcc-high-endpoints
            ServiceHosts     = (New-ServiceHosts 'graph.microsoft.us' 'outlook.office365.us' 'manage.office365.us' 'api-gov.securitycenter.microsoft.us')
        }
        $Map['USGovDoD'] = [pscustomobject]@{
            CloudEnvironment = 'USGovDoD'
            IsGovernment     = $true
            LoginHost        = 'login.microsoftonline.us'
            Authority        = 'https://login.microsoftonline.us'
            GraphHost        = 'dod-graph.microsoft.us'   # https://learn.microsoft.com/graph/deployments
            GraphUrl         = 'https://dod-graph.microsoft.us'
            GraphScope       = 'https://dod-graph.microsoft.us/.default'
            ExchangeHost     = 'webmail.apps.mil'   # https://learn.microsoft.com/powershell/module/exchangepowershell/connect-exchangeonline
            ManagementHost   = 'manage.protection.apps.mil'   # https://learn.microsoft.com/office/office-365-management-api/office-365-management-activity-api-reference
            DefenderHost     = 'api-gov.securitycenter.microsoft.us'   # https://learn.microsoft.com/defender-endpoint/gov (GCC High and DoD share it)
            SharePointSuffix = 'sharepoint-mil.us'   # https://learn.microsoft.com/microsoft-365/enterprise/microsoft-365-u-s-government-dod-endpoints
            ServiceHosts     = (New-ServiceHosts 'dod-graph.microsoft.us' 'webmail.apps.mil' 'manage.protection.apps.mil' 'api-gov.securitycenter.microsoft.us')
        }
        $script:CIPPCloudEndpointMap = $Map
    }

    $Endpoint = $null
    if ([string]::IsNullOrEmpty($CloudEnvironment) -or -not $script:CIPPCloudEndpointMap.TryGetValue($CloudEnvironment, [ref]$Endpoint)) {
        # The value is not echoed: it can come from a table row or a request.
        throw 'Unknown cloud environment. Expected exactly Commercial, USGovHigh or USGovDoD.'
    }
    # A copy, so a caller changing a property cannot alter the map for everyone else.
    return $Endpoint.PSObject.Copy()
}
