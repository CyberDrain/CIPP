# Test-CIPPCloudFeatureSupport (redanthrax/CIPP#4) is what background jobs ask before running a standard, alert, test,
# cache type or timer step for a tenant. Commercial tenants, the partner tenant and AllTenants are always supported and
# never reach the support matrix; government tenants are refused only what the matrix lists for their cloud.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTenantRequestCloud { param($TenantFilter) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPCloudFeatureSupport.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-CIPPCloudFeatureSupport.ps1')

    $script:PreviousRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $RepoRoot
    $script:Matrix = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'Config/cloudFeatureSupport.json')) | ConvertFrom-Json
    $script:AllEntries = foreach ($Section in 'pages', 'actions', 'standards', 'baselineStandards', 'alerts', 'tests', 'cacheTypes', 'timers') {
        foreach ($Entry in @($script:Matrix.$Section)) { [pscustomobject]@{ Type = $Section; Name = $Entry.name ?? $Entry.path ?? $Entry.url; Clouds = @($Entry.unsupportedClouds) } }
    }
}

AfterAll { $env:CIPPRootPath = $script:PreviousRoot }

Describe 'Test-CIPPCloudFeatureSupport' {
    BeforeEach { $script:CIPPCloudFeatureSupport = $null }

    Context 'commercial and partner scope (unchanged behaviour)' {
        It 'supports every listed feature for a Commercial tenant without reading the matrix' {
            Mock Get-CIPPTenantRequestCloud { 'Commercial' }
            Mock Get-CIPPCloudFeatureSupport {}
            foreach ($Entry in $script:AllEntries) {
                Test-CIPPCloudFeatureSupport -TenantFilter 'contoso.onmicrosoft.com' -Type $Entry.Type -Name $Entry.Name | Should -BeTrue -Because "$($Entry.Type)/$($Entry.Name)"
            }
            Should -Invoke Get-CIPPCloudFeatureSupport -Times 0 -Exactly
        }

        It 'supports everything for AllTenants, the partner tenant and an empty filter without looking up a cloud' {
            Mock Get-CIPPTenantRequestCloud { 'USGovHigh' }
            foreach ($Filter in 'AllTenants', 'allTenants', 'PartnerTenant', '', $null) {
                Test-CIPPCloudFeatureSupport -TenantFilter $Filter -Type 'standards' -Name 'TeamsGuestAccess' | Should -BeTrue
            }
            Should -Invoke Get-CIPPTenantRequestCloud -Times 0 -Exactly
        }

        It 'treats a cloud that cannot be resolved as supported, so the caller runs as before' {
            Mock Get-CIPPTenantRequestCloud { throw 'Unknown cloud environment' }
            Test-CIPPCloudFeatureSupport -TenantFilter 'x.onmicrosoft.com' -Type 'standards' -Name 'TeamsGuestAccess' | Should -BeTrue
        }

        It 'returns nothing from Get-CIPPCloudFeatureSupport for Commercial or no cloud' {
            Get-CIPPCloudFeatureSupport -Type 'standards' -Name 'TeamsGuestAccess' -CloudEnvironment 'Commercial' | Should -BeNullOrEmpty
            Get-CIPPCloudFeatureSupport -Type 'standards' -Name 'TeamsGuestAccess' | Should -BeNullOrEmpty
            $script:CIPPCloudFeatureSupport | Should -BeNullOrEmpty -Because 'the matrix is not even loaded'
        }
    }

    Context 'government tenants' {
        It 'refuses every listed feature for each cloud the entry names' {
            foreach ($Entry in $script:AllEntries) {
                foreach ($Cloud in $Entry.Clouds) {
                    Test-CIPPCloudFeatureSupport -Type $Entry.Type -Name $Entry.Name -CloudEnvironment $Cloud | Should -BeFalse -Because "$($Entry.Type)/$($Entry.Name) in $Cloud"
                }
            }
        }

        It 'supports features the matrix does not list' {
            Test-CIPPCloudFeatureSupport -Type 'standards' -Name 'AuditLog' -CloudEnvironment 'USGovHigh' | Should -BeTrue
            Test-CIPPCloudFeatureSupport -Type 'cacheTypes' -Name 'Users' -CloudEnvironment 'USGovDoD' | Should -BeTrue
            Test-CIPPCloudFeatureSupport -Type 'standards' -Name 'TeamsGuestAccess' -CloudEnvironment 'USGovHigh' | Should -BeFalse
        }

        It 'looks up the tenant cloud the request helpers route by' {
            Mock Get-CIPPTenantRequestCloud { 'USGovHigh' } -ParameterFilter { $TenantFilter -eq 'gov.onmicrosoft.us' }
            Test-CIPPCloudFeatureSupport -TenantFilter 'gov.onmicrosoft.us' -Type 'cacheTypes' -Name 'CsTeamsClientConfiguration' | Should -BeFalse
            Should -Invoke Get-CIPPTenantRequestCloud -Times 1 -Exactly
        }

        It 'matches the cloud case-sensitively, like Get-CIPPCloudEndpoint' {
            Get-CIPPCloudFeatureSupport -Type 'standards' -Name 'TeamsGuestAccess' -CloudEnvironment 'usgovhigh' | Should -BeNullOrEmpty
        }

        It 'returns the reason and evidence of the entry' {
            $Entry = Get-CIPPCloudFeatureSupport -Type 'standards' -Name 'TeamsGuestAccess' -CloudEnvironment 'USGovHigh'
            $Entry.Reason | Should -Match 'Teams admin ConfigAPI'
            $Entry.Evidence | Should -Match 'redanthrax/CIPP#3'
        }
    }

    Context 'a missing or corrupt matrix (fails open to the #3 refusals, never throws)' {
        BeforeEach { Mock Write-LogMessage {} }
        AfterEach { $env:CIPPRootPath = $RepoRoot }

        It 'gates nothing, logs once and does not re-read the file when <Case>' -ForEach @(
            @{ Case = 'the file is missing'; Content = $null }
            @{ Case = 'the file is not JSON'; Content = '{ not json' }
        ) {
            $Root = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().Guid)
            $null = New-Item -ItemType Directory -Path (Join-Path $Root 'Config') -Force
            if ($Content) { Set-Content -Path (Join-Path $Root 'Config/cloudFeatureSupport.json') -Value $Content }
            $env:CIPPRootPath = $Root
            try {
                { Test-CIPPCloudFeatureSupport -Type 'standards' -Name 'TeamsGuestAccess' -CloudEnvironment 'USGovHigh' } | Should -Not -Throw
                Test-CIPPCloudFeatureSupport -Type 'standards' -Name 'TeamsGuestAccess' -CloudEnvironment 'USGovHigh' | Should -BeTrue
                Get-CIPPCloudFeatureSupport -Type 'alerts' -Name 'DefenderStatus' -CloudEnvironment 'USGovDoD' | Should -BeNullOrEmpty
                Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' }
            } finally {
                Remove-Item -Path $Root -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'never reads the matrix for Commercial, so a broken file cannot affect a Commercial tenant' {
            $env:CIPPRootPath = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().Guid)
            Test-CIPPCloudFeatureSupport -Type 'standards' -Name 'TeamsGuestAccess' -CloudEnvironment 'Commercial' | Should -BeTrue
            $script:CIPPCloudFeatureSupport | Should -BeNullOrEmpty
            Should -Invoke Write-LogMessage -Times 0 -Exactly
        }
    }
}
