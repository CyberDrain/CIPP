# A baseline standard the tenant's cloud does not support (redanthrax/CIPP#4) is skipped by the engine like a disabled
# one: no licence lookup, no compare, no write, a Skipped-Cloud row with the reason, and one log line. A Commercial
# tenant goes through the engine exactly as before, and the orchestrator does no cloud work at all.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Get-CippTable { param($tablename) @{} }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) "$Value" }
    function Get-CIPPAzDataTableEntity { param($Filter) }
    function Add-CIPPBaselineHistoryEvent { param($TenantFilter, $Standard, $Mode, $TriggeredBy, $Outcome, $Detail, $RunId, $Remediated) }
    function Set-CIPPBaselineResult { param($Result, $Prior, $RunId, $Detail) }
    function Send-CIPPBaselineAlert { param($Result) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CIPPTenantCapabilities { param($TenantFilter) }
    function Get-CIPPBaselineDefinition { param($Name) }
    function Get-CIPPTenantRequestCloud { param($TenantFilter) }

    . (Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public/Helpers/Invoke-CIPPBaselineStandard.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPCloudFeatureSupport.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Functions/Test-CIPPCloudFeatureSupport.ps1')

    $script:Definition = Get-Content (Join-Path $script:RepoRoot 'Config/BaselineStandards/Teams Standards/TeamsGuestAccess.json') -Raw | ConvertFrom-Json
    function New-EngineItem {
        @{ TenantFilter = 'tenant.example'; Standard = 'TeamsGuestAccess'; BaseName = 'TeamsGuestAccess'; Variables = [PSCustomObject]@{ AllowGuestUser = $false }; Tiers = @(); AlertEnabled = $false; RemediateEnabled = $true }
    }

    $script:PreviousRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $script:RepoRoot
}

AfterAll { $env:CIPPRootPath = $script:PreviousRoot }

Describe 'Engine: cloud support' {
    BeforeEach {
        $script:CIPPCloudFeatureSupport = $null
        Mock Get-CIPPBaselineDefinition { $script:Definition }
        Mock Set-CIPPBaselineResult {}
        Mock Write-LogMessage {}
        # No licence: a Commercial run stops at the licence gate, which proves it went past the cloud check.
        Mock Get-CIPPTenantCapabilities { [PSCustomObject]@{} }
    }

    It 'skips an unsupported standard for a government tenant before the licence check, with the reason on the row' {
        Mock Get-CIPPTenantRequestCloud { 'USGovHigh' }
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run'

        $Result.Outcome | Should -Be 'Skipped-Cloud'
        $Result.Status | Should -Be 'No Data'
        $Result.Remediated | Should -BeFalse
        Should -Invoke Get-CIPPTenantCapabilities -Times 0 -Exactly
        Should -Invoke Set-CIPPBaselineResult -Times 1 -Exactly -ParameterFilter { $Detail -eq 'Not supported for USGovHigh tenants - skipped.' }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $tenant -eq 'tenant.example' -and $Sev -eq 'Info' -and $message -match 'not supported for USGovHigh tenants' }
    }

    It 'returns nothing for a grade-only verification on a government tenant' {
        Mock Get-CIPPTenantRequestCloud { 'USGovDoD' }
        Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'oneoff' -GradeOnly | Should -BeNullOrEmpty
        Should -Invoke Set-CIPPBaselineResult -Times 0 -Exactly
    }

    It 'leaves a Commercial tenant on the normal path (here: the licence gate)' {
        Mock Get-CIPPTenantRequestCloud { 'Commercial' }
        Mock Get-CIPPCloudFeatureSupport {}
        $Result = Invoke-CIPPBaselineStandard -Item (New-EngineItem) -Mode 'run'

        $Result.Outcome | Should -Be 'Skipped-License'
        Should -Invoke Get-CIPPTenantCapabilities -Times 1 -Exactly
        Should -Invoke Get-CIPPCloudFeatureSupport -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $message -match 'not supported for' }
    }
}

Describe 'Orchestrator: no cloud work for any estate' {
    It 'Start-CIPPBaselineOrchestrator does not read the tenant list or the support matrix (the engine logs government skips)' {
        $Source = Get-Content -Raw (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Entrypoints/Orchestrator Functions/Start-CIPPBaselineOrchestrator.ps1')
        $Source | Should -Not -Match 'Get-Tenants'
        $Source | Should -Not -Match 'CloudFeatureSupport'
        $Source | Should -Not -Match 'cloudEnvironment'
    }
}
