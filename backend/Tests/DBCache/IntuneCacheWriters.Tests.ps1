# Each Intune cache type has one nightly writer, and every report page's Sync names a collector that exists.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:Collectors = Get-ChildItem (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache') -Filter 'Set-CIPPDBCache*.ps1'
    $script:PagesRoot = Join-Path (Split-Path -Parent $RepoRoot) 'frontend/src/pages'
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntunePolicyListDefinitions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPDBCacheSchedule.ps1')
}

Describe 'Intune cache writers' {
    It 'writes IntuneDeviceCompliancePolicies and its device statuses only from the IntunePolicies umbrella' {
        $Definition = @(Get-CIPPIntunePolicyListDefinitions).Where({ $_.CacheType -eq 'IntuneDeviceCompliancePolicies' })[0]
        $Definition.FetchDeviceStatuses | Should -BeTrue
        @($script:Collectors | Where-Object { (Get-Content $_.FullName -Raw) -match "'IntuneDeviceCompliancePolicies'" }).Name | Should -BeNullOrEmpty
        (Get-CIPPDBCacheSchedule).Intune.Types | Should -Contain 'IntunePolicies'
    }

    It 'names an existing collector in every report page sync' {
        $Names = foreach ($Page in (Get-ChildItem $script:PagesRoot -Recurse -Include '*.js', '*.jsx')) {
            foreach ($Match in [regex]::Matches((Get-Content $Page.FullName -Raw), 'cacheName:\s*[''"]([A-Za-z0-9]+)[''"]')) { $Match.Groups[1].Value }
        }
        $Registry = Get-Content (Join-Path $RepoRoot 'Config/CIPPDBCacheTypes.json') -Raw | ConvertFrom-Json
        $Missing = foreach ($Name in ($Names | Sort-Object -Unique)) {
            $Collector = ($Registry | Where-Object type -EQ $Name).collectedBy ?? $Name
            if (-not ($script:Collectors.BaseName -contains "Set-CIPPDBCache$Collector")) { $Name }
        }
        $Names | Should -Not -BeNullOrEmpty
        $Missing | Should -BeNullOrEmpty
    }
}
