function ConvertTo-CIPPCloudPortalUrl {
    <#
    .SYNOPSIS
        Points a Microsoft admin portal link at a government tenant's portal.
    .DESCRIPTION
        Links CIPP builds for people (tenant list portal columns, extension sync documentation) name the
        commercial admin portals. A government tenant is managed from its cloud's portals, so for a
        USGovHigh or USGovDoD tenant the host of a commercial portal link is replaced with the documented
        government host, and $null is returned when Microsoft documents none (callers leave the link out).
        The host map and its sources are 'portalHosts' in Config/cloudFeatureSupport.json, the file the
        frontend reads too (redanthrax/CIPP#4).

        Commercial, no cloud, an unknown cloud, a URL that is not a listed commercial portal, and an
        unreadable map all return the URL unchanged. Commercial never reads the file.
    .PARAMETER Url
        The link as built for the commercial cloud.
    .PARAMETER CloudEnvironment
        The tenant's cloud: Commercial, USGovHigh or USGovDoD.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Url,
        [string]$CloudEnvironment
    )

    if ([string]::IsNullOrEmpty($CloudEnvironment) -or $CloudEnvironment -ceq 'Commercial' -or $Url -isnot [string]) { return $Url }

    if ($null -eq $script:CIPPCloudPortalHosts) {
        $Map = @{}
        try {
            $Path = Join-Path $env:CIPPRootPath 'Config\cloudFeatureSupport.json'
            $PortalHosts = ([System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop).portalHosts
            foreach ($Cloud in @('USGovHigh', 'USGovDoD')) {
                $Hosts = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($Property in @($PortalHosts.$Cloud.PSObject.Properties)) { $Hosts[$Property.Name] = $Property.Value }
                if ($Hosts.Count -gt 0) { $Map[$Cloud] = $Hosts }
            }
        } catch {
            Write-Information "Could not load portalHosts from Config/cloudFeatureSupport.json; portal links are left unchanged: $($_.Exception.Message)"
        }
        $script:CIPPCloudPortalHosts = $Map
    }

    $Hosts = $script:CIPPCloudPortalHosts[$CloudEnvironment]
    if (-not $Hosts -or $Url -notmatch '^https://([^/?#:]+)') { return $Url }
    $Target = $null
    if (-not $Hosts.TryGetValue($Matches[1], [ref]$Target)) { return $Url }
    if ([string]::IsNullOrEmpty($Target)) { return $null }
    return "https://$Target$($Url.Substring($Matches[0].Length))"
}
