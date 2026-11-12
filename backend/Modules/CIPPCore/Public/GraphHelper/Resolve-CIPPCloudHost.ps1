function Resolve-CIPPCloudHost {
    <#
    .SYNOPSIS
        Maps a Microsoft API host to the host CIPP must use for a tenant's cloud.
    .DESCRIPTION
        The one place that decides which host a request or token for a government tenant may use
        (redanthrax/CIPP#3). For a Commercial cloud the host is returned unchanged. For USGovHigh or
        USGovDoD:

          - a commercial service host from Get-CIPPCloudEndpoint (graph.microsoft.com,
            outlook.office365.com, manage.office.com, api.securitycenter.microsoft.com, plus the older
            api.securitycenter.windows.com) becomes that cloud's literal host for the same service
          - a host of that cloud (graph.microsoft.us, ...) and a SharePoint host under that cloud's
            SharePoint suffix (*.sharepoint.us, *.sharepoint-mil.us) are returned as they are
          - anything else throws: a host with no documented government equivalent (Teams admin,
            Security & Compliance, Partner Center, admin.microsoft.com, reports.office.com, ...),
            another cloud's host, or a commercial SharePoint host

        Host names compare case-insensitively (DNS); the cloud name exactly (Get-CIPPCloudEndpoint).
        The returned host is always one of the literals in Get-CIPPCloudEndpoint or the input itself
        after it matched a literal suffix - it is never built from stored or request data.
    .PARAMETER HostName
        The host name (no scheme, port or path).
    .PARAMETER CloudEnvironment
        Commercial, USGovHigh or USGovDoD (exact case).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$HostName,
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [AllowNull()]
        [string]$CloudEnvironment
    )

    $Endpoint = Get-CIPPCloudEndpoint -CloudEnvironment $CloudEnvironment
    if (-not $Endpoint.IsGovernment) { return $HostName }

    if (-not $script:CIPPCommercialHostService) {
        $Map = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Commercial = Get-CIPPCloudEndpoint -CloudEnvironment 'Commercial'
        foreach ($Service in $Commercial.ServiceHosts.Keys) { $Map[$Commercial.ServiceHosts[$Service]] = $Service }
        # The older name of the Defender for Endpoint API, still used as its token resource.
        $Map['api.securitycenter.windows.com'] = 'Defender'
        $script:CIPPCommercialHostService = $Map
    }

    $Service = $null
    if ($script:CIPPCommercialHostService.TryGetValue($HostName, [ref]$Service)) {
        return $Endpoint.ServiceHosts[$Service]
    }
    foreach ($OwnHost in $Endpoint.ServiceHosts.Values) {
        if ([string]::Equals($HostName, $OwnHost, [System.StringComparison]::OrdinalIgnoreCase)) { return $OwnHost }
    }
    # Tenant SharePoint hosts (contoso.sharepoint.us, contoso-admin.sharepoint.us) come from the
    # tenant's own root site, so only the suffix can be fixed here. A commercial one is not rewritten:
    # the tenant name in front of the suffix is not ours to vouch for.
    $SharePointSuffix = '.' + $Endpoint.SharePointSuffix
    if ($HostName.Length -gt $SharePointSuffix.Length -and $HostName.EndsWith($SharePointSuffix, [System.StringComparison]::OrdinalIgnoreCase) -and
        $HostName -match '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\z') {
        return $HostName
    }

    # Only echo something that looks like a host name.
    $Shown = if ($HostName -match '^[A-Za-z0-9.-]{1,253}\z') { $HostName } else { 'this host' }
    throw "$Shown is not supported for government tenants ($($Endpoint.CloudEnvironment)): Microsoft documents no equivalent host CIPP can use (see redanthrax/CIPP#3)."
}
