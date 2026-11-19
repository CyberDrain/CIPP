function Resolve-CIPPCloudHost {
    <#
    .SYNOPSIS
        Maps a Microsoft API host to the host CIPP must use for a tenant's cloud.
    .DESCRIPTION
        Commercial hosts are returned unchanged. For a government cloud the result is always a literal from
        Get-CIPPCloudEndpoint or a host under its SharePoint suffix; anything else throws.
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
    # Tenant SharePoint hosts: only the suffix is checked; commercial ones are not rewritten.
    $SharePointSuffix = '.' + $Endpoint.SharePointSuffix
    if ($HostName.Length -gt $SharePointSuffix.Length -and $HostName.EndsWith($SharePointSuffix, [System.StringComparison]::OrdinalIgnoreCase) -and
        $HostName -match '^[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\z') {
        return $HostName
    }

    # Only echo something that looks like a host name.
    $Shown = if ($HostName -match '^[A-Za-z0-9.-]{1,253}\z') { $HostName } else { 'this host' }
    throw "$Shown is not supported for government tenants ($($Endpoint.CloudEnvironment)): Microsoft documents no equivalent host CIPP can use."
}
