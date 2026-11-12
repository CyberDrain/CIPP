function Get-CIPPCloudFeatureSupport {
    <#
    .SYNOPSIS
        Returns the support-matrix entry that marks a feature unsupported in a cloud, or nothing.
    .DESCRIPTION
        Reads Config\cloudFeatureSupport.json, shared with the frontend. Commercial never reads the file.
    .PARAMETER Type
        The matrix section: pages, actions, standards, baselineStandards, alerts, tests, cacheTypes or timers.
    .PARAMETER Name
        The feature's key in that section.
    .PARAMETER CloudEnvironment
        Commercial, USGovHigh or USGovDoD.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('pages', 'actions', 'standards', 'baselineStandards', 'alerts', 'tests', 'cacheTypes', 'timers')]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$CloudEnvironment
    )

    if ([string]::IsNullOrEmpty($CloudEnvironment) -or $CloudEnvironment -ceq 'Commercial') { return }

    if (-not $script:CIPPCloudFeatureSupport) {
        $Sections = @('pages', 'actions', 'standards', 'baselineStandards', 'alerts', 'tests', 'cacheTypes', 'timers')
        $Index = @{}
        try {
            $Path = Join-Path $env:CIPPRootPath 'Config\cloudFeatureSupport.json'
            $Matrix = [System.IO.File]::ReadAllText($Path) | ConvertFrom-Json -ErrorAction Stop
            foreach ($Section in $Sections) {
                $Lookup = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($Entry in @($Matrix.$Section)) {
                    $Key = $Entry.name ?? $Entry.path ?? $Entry.url
                    if ([string]::IsNullOrEmpty($Key)) { continue }
                    $Source = $Matrix.sources.($Entry.source)
                    $Lookup[$Key] = [PSCustomObject]@{
                        Name              = $Key
                        UnsupportedClouds = @($Entry.unsupportedClouds)
                        Source            = $Entry.source
                        Reason            = $Source.reason
                        Evidence          = $Source.evidence
                    }
                }
                $Index[$Section] = $Lookup
            }
        } catch {
            # Gate nothing rather than fail whole jobs; the request helpers still refuse unsupported gov hosts.
            $LoadError = $_.Exception.Message
            $Index = @{}
            foreach ($Section in $Sections) {
                $Index[$Section] = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            }
            try { Write-LogMessage -API 'CloudFeatureSupport' -message "Could not load Config/cloudFeatureSupport.json; background jobs skip no features for government tenants: $LoadError" -sev Error } catch {}
        }
        $script:CIPPCloudFeatureSupport = $Index
    }

    $Entry = $null
    if ($script:CIPPCloudFeatureSupport[$Type].TryGetValue($Name, [ref]$Entry) -and $Entry.UnsupportedClouds -ccontains $CloudEnvironment) {
        return $Entry
    }
}
