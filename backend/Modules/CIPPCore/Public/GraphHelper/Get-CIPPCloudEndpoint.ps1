function Get-CIPPCloudEndpoint {
    <#
    .SYNOPSIS
        Returns the fixed identity and API hosts for a Microsoft cloud.
    .DESCRIPTION
        Exact, case-sensitive match on Commercial, USGovHigh or USGovDoD; anything else throws. Services with
        no documented government host are left out on purpose.
    .PARAMETER CloudEnvironment
        Commercial, USGovHigh or USGovDoD (exact case).
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
        # Read-only so callers can't change the shared map through the copy below.
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
    # Copy so callers can't alter the shared map.
    return $Endpoint.PSObject.Copy()
}
