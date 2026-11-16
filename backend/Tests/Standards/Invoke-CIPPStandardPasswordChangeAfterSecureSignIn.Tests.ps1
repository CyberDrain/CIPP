# Pester tests for Invoke-CIPPStandardPasswordChangeAfterSecureSignIn.
#
# The standard owns exactly one boolean on the Password authentication method configuration.
# These tests pin that it grades against the state the template chose (either direction), that
# a tenant where the preview property is absent reads as the Microsoft default (false), and
# that remediation goes through the shared helper with nothing but that one setting.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Join-Path $RepoRoot 'Modules/CIPPStandards/Public/Standards/Invoke-CIPPStandardPasswordChangeAfterSecureSignIn.ps1'

    function New-GraphGetRequest { [CmdletBinding()] param($Uri, $tenantid, $AsApp) }
    function Set-CIPPAuthenticationPolicy { [CmdletBinding()] param($Tenant, $APIName, $AuthenticationMethodId, [bool]$Enabled, $GroupIds, $ExcludeGroupIds, $PasswordAllowChangeAfterSecureSignIn) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Get-CippException { [CmdletBinding()] param($Exception) [PSCustomObject]@{ NormalizedError = "$Exception" } }

    . $StandardPath
    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardPasswordChangeAfterSecureSignIn' {
    BeforeEach {
        Mock New-GraphGetRequest { [PSCustomObject]@{ id = 'Password'; state = 'enabled'; allowPasswordChangeAfterSecureSignIn = $false } }
        Mock Set-CIPPAuthenticationPolicy { }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
        Mock Set-CIPPStandardsCompareField { }
    }

    It 'enables the setting through the shared helper, sending no targeting' {
        $Settings = @{ remediate = $true; state = [PSCustomObject]@{ label = 'Enabled'; value = 'true' } }
        Invoke-CIPPStandardPasswordChangeAfterSecureSignIn -Tenant $script:Tenant -Settings $Settings

        Should -Invoke Set-CIPPAuthenticationPolicy -Times 1 -Exactly -ParameterFilter {
            $AuthenticationMethodId -eq 'Password' -and
            $PasswordAllowChangeAfterSecureSignIn -eq $true -and
            $null -eq $GroupIds -and $null -eq $ExcludeGroupIds
        }
    }

    It 'disables the setting when the template chose Disabled and the tenant has it on' {
        Mock New-GraphGetRequest { [PSCustomObject]@{ id = 'Password'; state = 'enabled'; allowPasswordChangeAfterSecureSignIn = $true } }
        Invoke-CIPPStandardPasswordChangeAfterSecureSignIn -Tenant $script:Tenant -Settings @{ remediate = $true; state = 'false' }

        Should -Invoke Set-CIPPAuthenticationPolicy -Times 1 -Exactly -ParameterFilter {
            $AuthenticationMethodId -eq 'Password' -and $PasswordAllowChangeAfterSecureSignIn -eq $false
        }
    }

    It 'does not write or alert when the tenant already matches' {
        Invoke-CIPPStandardPasswordChangeAfterSecureSignIn -Tenant $script:Tenant -Settings @{ remediate = $true; alert = $true; state = 'false' }

        Should -Invoke Set-CIPPAuthenticationPolicy -Times 0 -Exactly
        Should -Invoke Write-StandardsAlert -Times 0 -Exactly
    }

    It 'treats a tenant without the preview property as disabled' {
        Mock New-GraphGetRequest { [PSCustomObject]@{ id = 'Password'; state = 'enabled' } }
        Invoke-CIPPStandardPasswordChangeAfterSecureSignIn -Tenant $script:Tenant -Settings @{ remediate = $true; alert = $true; report = $true; state = 'false' }

        Should -Invoke Set-CIPPAuthenticationPolicy -Times 0 -Exactly
        Should -Invoke Write-StandardsAlert -Times 0 -Exactly
        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            $CurrentValue.allowPasswordChangeAfterSecureSignIn -eq $false -and $ExpectedValue.allowPasswordChangeAfterSecureSignIn -eq $false
        }
    }

    It 'alerts with the standard name when the tenant differs from the chosen state' {
        Invoke-CIPPStandardPasswordChangeAfterSecureSignIn -Tenant $script:Tenant -Settings @{ alert = $true; state = 'true'; standardId = 'std-1' }

        Should -Invoke Write-StandardsAlert -Times 1 -Exactly -ParameterFilter {
            $standardName -eq 'PasswordChangeAfterSecureSignIn' -and $standardId -eq 'std-1'
        }
    }

    It 'reports current and expected as booleans under the standard field name' {
        Invoke-CIPPStandardPasswordChangeAfterSecureSignIn -Tenant $script:Tenant -Settings @{ report = $true; state = 'true' }

        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            $FieldName -eq 'standards.PasswordChangeAfterSecureSignIn' -and
            $CurrentValue.allowPasswordChangeAfterSecureSignIn -is [bool] -and $CurrentValue.allowPasswordChangeAfterSecureSignIn -eq $false -and
            $ExpectedValue.allowPasswordChangeAfterSecureSignIn -is [bool] -and $ExpectedValue.allowPasswordChangeAfterSecureSignIn -eq $true
        }
    }

    It 'does nothing when no state was chosen' {
        Invoke-CIPPStandardPasswordChangeAfterSecureSignIn -Tenant $script:Tenant -Settings @{ remediate = $true; report = $true }

        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        Should -Invoke Set-CIPPAuthenticationPolicy -Times 0 -Exactly
        Should -Invoke Set-CIPPStandardsCompareField -Times 0 -Exactly
    }
}
