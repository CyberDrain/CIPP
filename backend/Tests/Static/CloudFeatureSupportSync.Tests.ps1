# The cloud support matrix (redanthrax/CIPP#4): the backend reads backend/Config/cloudFeatureSupport.json, the UI
# imports frontend/src/data/cloudFeatureSupport.json. Edit the frontend copy and copy it over the backend one.
# The baseline standard and test lists are derived from the definitions they gate; these tests re-derive them so a
# new Teams, Security & Compliance or Copilot admin baseline standard, or a new test that reads only an unsupported cache type,
# fails here until the matrix lists it.

BeforeDiscovery {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Matrix = [System.IO.File]::ReadAllText((Join-Path $BackendRoot 'Config/cloudFeatureSupport.json')) | ConvertFrom-Json
    $script:Sections = foreach ($Name in 'pages', 'actions', 'standards', 'baselineStandards', 'alerts', 'tests', 'cacheTypes', 'timers') {
        @{ Section = $Name; Entries = @($Matrix.$Name) }
    }
}

BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $RepoRoot = Split-Path -Parent $BackendRoot
    $script:BackendRoot = $BackendRoot
    $script:FrontendPath = Join-Path $RepoRoot 'frontend/src/data/cloudFeatureSupport.json'
    $script:BackendPath = Join-Path $BackendRoot 'Config/cloudFeatureSupport.json'
    $script:Matrix = [System.IO.File]::ReadAllText($script:BackendPath) | ConvertFrom-Json
    $script:NavConfig = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'frontend/src/layouts/config.jsx'))
    $script:UnsupportedCache = @($script:Matrix.cacheTypes.name)

    # The executors and flags whose calls #3 refuses for government tenants, or that only call the Copilot admin API.
    $script:UnsupportedExecutors = @('TeamsRequest', 'TeamsFederationConfiguration', 'QuarantineRequestAlert', 'DlpCompliancePolicyTemplate',
        'RetentionCompliancePolicyTemplate', 'SensitiveInfoTypeTemplate', 'SensitivityLabelTemplate', 'DefenderCompliancePolicy', 'DisableSelfServiceLicenses',
        'CopilotLimitedMode')
    # Graph paths government Graph does not have: a GraphRequest step that calls one is unsupported.
    $script:UnsupportedGraphPaths = '"uri":"(https://graph\.microsoft\.com/(beta|v1\.0)/)?/?copilot/admin/'
}

Describe 'cloudFeatureSupport.json copies' {
    It 'keeps the backend copy identical to the frontend copy' {
        $Read = { param($Path) [System.IO.File]::ReadAllText($Path).Replace("`r`n", "`n") }
        & $Read $script:BackendPath | Should -BeExactly (& $Read $script:FrontendPath) -Because 'copy frontend/src/data/cloudFeatureSupport.json to backend/Config/cloudFeatureSupport.json'
    }
}

Describe 'cloudFeatureSupport.json <Section>' -ForEach $script:Sections {
    It 'names a known source and only government clouds for every entry' {
        foreach ($Entry in $Entries) {
            $Key = $Entry.name ?? $Entry.path ?? $Entry.url
            $Key | Should -Not -BeNullOrEmpty
            $script:Matrix.sources.($Entry.source) | Should -Not -BeNullOrEmpty -Because "$Key needs a source with a reason and evidence"
            @($Entry.unsupportedClouds).Count | Should -BeGreaterThan 0 -Because "$Key must say which clouds it is unsupported in"
            foreach ($Cloud in $Entry.unsupportedClouds) { $Cloud | Should -BeIn @('USGovHigh', 'USGovDoD') -Because 'Commercial is never gated' }
        }
    }

    It 'has no duplicate keys' {
        @($Entries | ForEach-Object { $_.name ?? $_.path ?? $_.url } | Group-Object | Where-Object Count -GT 1).Name | Should -BeNullOrEmpty
    }
}

Describe 'cloudFeatureSupport.json entries exist' {
    It 'names standards that exist' {
        foreach ($Name in $script:Matrix.standards.name) {
            @(Get-ChildItem -Path (Join-Path $script:BackendRoot 'Modules/CIPPStandards') -Recurse -Filter "Invoke-CIPPStandard$Name.ps1").Count | Should -Be 1 -Because "standard $Name"
        }
    }
    It 'names cache types that exist' {
        foreach ($Name in $script:Matrix.cacheTypes.name) {
            @(Get-ChildItem -Path (Join-Path $script:BackendRoot 'Modules') -Recurse -Filter "Set-CIPPDBCache$Name.ps1").Count | Should -Be 1 -Because "cache type $Name"
        }
    }
    It 'names alerts that exist in the alert catalog' {
        $Catalog = @(([System.IO.File]::ReadAllText((Join-Path $script:BackendRoot 'Config/alerts.json')) | ConvertFrom-Json).name)
        foreach ($Name in $script:Matrix.alerts.name) { $Name | Should -BeIn $Catalog }
    }
    It 'names pages that are in the navigation' {
        foreach ($Path in $script:Matrix.pages.path) { $script:NavConfig | Should -Match ([regex]::Escape("'$Path'")) -Because "page $Path" }
    }
}

Describe 'derived lists' {
    It 'lists exactly the baseline standards that use an unsupported executor, compliance step, Graph path or cache type' {
        $Derived = foreach ($File in Get-ChildItem -Path (Join-Path $script:BackendRoot 'Config/BaselineStandards') -Recurse -Filter '*.json') {
            $Definition = try { [System.IO.File]::ReadAllText($File.FullName) | ConvertFrom-Json } catch { $null }
            if (-not $Definition.name) { continue }
            $Remediate = $Definition.remediate
            $RemediateJson = if ($Remediate) { $Remediate | ConvertTo-Json -Depth 50 -Compress } else { '' }
            if ($Remediate.executor -in $script:UnsupportedExecutors -or
                $RemediateJson -match '"compliance":true' -or
                $RemediateJson -match $script:UnsupportedGraphPaths -or
                ($Definition.read.cacheType -and $Definition.read.cacheType -in $script:UnsupportedCache)) {
                $Definition.name
            }
        }
        @($script:Matrix.baselineStandards.name | Sort-Object) | Should -Be @($Derived | Sort-Object -Unique)
    }

    It 'lists every classic standard and cache type that calls the Copilot admin API' {
        $Sets = @(
            @{ Folder = 'Modules/CIPPStandards'; Prefix = 'Invoke-CIPPStandard'; Listed = @($script:Matrix.standards.name) }
            @{ Folder = 'Modules/CIPPDB'; Prefix = 'Set-CIPPDBCache'; Listed = $script:UnsupportedCache }
        )
        foreach ($Set in $Sets) {
            foreach ($File in Get-ChildItem -Path (Join-Path $script:BackendRoot $Set.Folder) -Recurse -Filter "$($Set.Prefix)*.ps1") {
                if ([System.IO.File]::ReadAllText($File.FullName) -match 'copilot/admin/') {
                    ($File.BaseName -replace "^$($Set.Prefix)", '') | Should -BeIn $Set.Listed -Because "$($File.Name) calls copilot/admin, which government Graph does not have"
                }
            }
        }
    }

    It 'lists exactly the tests that read only unsupported cache types' {
        $Derived = foreach ($File in Get-ChildItem -Path (Join-Path $script:BackendRoot 'Modules/CIPPTests') -Recurse -Filter 'Invoke-CippTest*.ps1') {
            $Types = @([regex]::Matches([System.IO.File]::ReadAllText($File.FullName), "Get-CIPPTestData\b[^\r\n]*?-Type\s+['""]?(\w+)") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
            if ($Types.Count -gt 0 -and @($Types | Where-Object { $_ -notin $script:UnsupportedCache }).Count -eq 0) {
                $File.BaseName -replace '^Invoke-CippTest', ''
            }
        }
        @($script:Matrix.tests.name | Sort-Object) | Should -Be @($Derived | Sort-Object -Unique)
    }
}
