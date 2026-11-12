# Tests that read only cache types a tenant's cloud does not support (redanthrax/CIPP#4) are not run for that tenant:
# one informational log line per suite run instead of a "cache not found" result per test. Commercial tenants run
# every test in the suite, as before.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPTestCollection.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPCloudFeatureSupport.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-CIPPCloudFeatureSupport.ps1')

    function Get-CIPPTenantRequestCloud { param($TenantFilter) }
    function Get-CippTestSuitePatterns { @{ CIS = 'Invoke-CippTestCIS_*' } }
    function Get-CippTable { param($tablename) @{ Context = 'stub' } }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    # The collection runs the suite's tests from the CIPPTests module's exports.
    $null = New-Module -Name CIPPTests -ScriptBlock {
        function Invoke-CippTestCIS_8_1_1 { param($Tenant) $global:CippCloudTestRan.Add('CIS_8_1_1') }
        function Invoke-CippTestCIS_1_1_1 { param($Tenant) $global:CippCloudTestRan.Add('CIS_1_1_1') }
    } | Import-Module -Force -PassThru

    $script:PreviousRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $RepoRoot
}

AfterAll {
    $env:CIPPRootPath = $script:PreviousRoot
    Remove-Module -Name CIPPTests -Force -ErrorAction SilentlyContinue
    Remove-Variable -Name CippCloudTestRan -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Invoke-CIPPTestCollection cloud support' {
    BeforeEach {
        $script:CIPPCloudFeatureSupport = $null
        $script:CippTestSuiteCommands = $null
        $global:CippCloudTestRan = [System.Collections.Generic.List[string]]::new()
        Mock Write-LogMessage {}
    }

    It 'runs every test for a Commercial tenant and logs nothing' {
        Mock Get-CIPPTenantRequestCloud { 'Commercial' }
        Mock Get-CIPPCloudFeatureSupport {}
        $Result = Invoke-CIPPTestCollection -SuiteName 'CIS' -TenantFilter 'contoso.onmicrosoft.com' 6>$null

        @($global:CippCloudTestRan | Sort-Object) | Should -Be @('CIS_1_1_1', 'CIS_8_1_1')
        $Result.Total | Should -Be 2
        Should -Invoke Write-LogMessage -Times 0 -Exactly
        Should -Invoke Get-CIPPCloudFeatureSupport -Times 0 -Exactly
    }

    It 'skips the Teams-only test for a government tenant with one informational log line' {
        Mock Get-CIPPTenantRequestCloud { 'USGovDoD' }
        $Result = Invoke-CIPPTestCollection -SuiteName 'CIS' -TenantFilter 'gov.onmicrosoft.us' 6>$null

        @($global:CippCloudTestRan) | Should -Be @('CIS_1_1_1')
        $Result.Total | Should -Be 1
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Info' -and $message -like '*1 CIS test(s) not supported for USGovDoD tenants: CIS_8_1_1' }
    }
}
