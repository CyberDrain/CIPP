# Pester tests for Invoke-CIPPStandardTeamsExternalChatWithAnyone
#
# The radio's default used to be its label ('Disabled'), so templates saved without clicking a radio
# hold a string [Convert]::ToBoolean cannot read. Those templates must still run.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-CIPPStandardTeamsExternalChatWithAnyone.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $StandardPath) { throw 'Could not locate Invoke-CIPPStandardTeamsExternalChatWithAnyone.ps1 under Modules/' }

    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-TeamsRequestV2 { [CmdletBinding()] param($TenantFilter, $Type, $Action, $Identity, $Parameters) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $Tenant) }
    function Get-CippException { [CmdletBinding()] param($Exception) }

    . $StandardPath

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardTeamsExternalChatWithAnyone saved setting values' {
    BeforeEach {
        $script:SetParams = $null
        $script:Compare = $null
        $script:TenantValue = $null

        Mock -CommandName Test-CIPPStandardLicense -MockWith { $true }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-StandardsAlert -MockWith { }
        Mock -CommandName Set-CIPPStandardsCompareField -MockWith {
            param($FieldName, $CurrentValue, $ExpectedValue)
            $script:Compare = @{ Current = $CurrentValue; Expected = $ExpectedValue }
        }
        Mock -CommandName New-TeamsRequestV2 -MockWith {
            param($Action, $Parameters)
            if ($Action -eq 'Set') { $script:SetParams = $Parameters; return }
            [pscustomobject]@{ Identity = 'Global'; UseB2BInvitesToAddExternalUsers = $script:TenantValue }
        }
    }

    It 'reads <Label> as <Expected> and writes it when the tenant differs' -ForEach @(
        @{ Label = "'true'"; Value = 'true'; Expected = $true }
        @{ Label = "'false'"; Value = 'false'; Expected = $false }
        @{ Label = "'Disabled'"; Value = 'Disabled'; Expected = $false }
        @{ Label = '$true'; Value = $true; Expected = $true }
        @{ Label = '$false'; Value = $false; Expected = $false }
        @{ Label = '$null'; Value = $null; Expected = $false }
    ) {
        $script:TenantValue = -not $Expected
        $Settings = [pscustomobject]@{ remediate = $true; report = $true; UseB2BInvitesToAddExternalUsers = $Value }

        { Invoke-CIPPStandardTeamsExternalChatWithAnyone -Tenant $script:Tenant -Settings $Settings } | Should -Not -Throw

        $script:SetParams.Identity | Should -BeExactly 'Global'
        $script:SetParams.UseB2BInvitesToAddExternalUsers | Should -BeOfType [bool]
        $script:SetParams.UseB2BInvitesToAddExternalUsers | Should -Be $Expected
        $script:Compare.Expected.UseB2BInvitesToAddExternalUsers | Should -Be $Expected
    }

    It 'sends nothing for <Label> when the tenant already matches' -ForEach @(
        @{ Label = "'true'"; Value = 'true'; Expected = $true }
        @{ Label = "'false'"; Value = 'false'; Expected = $false }
        @{ Label = "'Disabled'"; Value = 'Disabled'; Expected = $false }
        @{ Label = '$true'; Value = $true; Expected = $true }
        @{ Label = '$false'; Value = $false; Expected = $false }
        @{ Label = '$null'; Value = $null; Expected = $false }
    ) {
        $script:TenantValue = $Expected
        $Settings = [pscustomobject]@{ remediate = $true; alert = $true; report = $true; UseB2BInvitesToAddExternalUsers = $Value }

        { Invoke-CIPPStandardTeamsExternalChatWithAnyone -Tenant $script:Tenant -Settings $Settings } | Should -Not -Throw

        Should -Invoke -CommandName New-TeamsRequestV2 -Times 0 -Exactly -ParameterFilter { $Action -eq 'Set' }
        Should -Invoke -CommandName Write-StandardsAlert -Times 0 -Exactly
        $script:Compare.Current.UseB2BInvitesToAddExternalUsers | Should -Be $script:Compare.Expected.UseB2BInvitesToAddExternalUsers
    }

    It 'treats a template without the setting as disabled' {
        $script:TenantValue = $true

        Invoke-CIPPStandardTeamsExternalChatWithAnyone -Tenant $script:Tenant -Settings ([pscustomobject]@{ remediate = $true })

        $script:SetParams.UseB2BInvitesToAddExternalUsers | Should -BeFalse
    }
}
