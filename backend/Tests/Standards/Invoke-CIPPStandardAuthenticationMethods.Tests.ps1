# Pester tests for the Password setting in Invoke-CIPPStandardAuthenticationMethods.
#
# The multi-method standard gained one optional field for the Password method's
# allowPasswordChangeAfterSecureSignIn setting. Templates saved before the field existed must
# behave exactly as they did: no Password grade, no Password write, no Password key in the
# report. When the field is set, Password is graded on that one setting only - its state and
# targeting are never part of the grade or the write.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $StandardPath = Join-Path $RepoRoot 'Modules/CIPPStandards/Public/Standards/Invoke-CIPPStandardAuthenticationMethods.ps1'

    function New-GraphGetRequest { [CmdletBinding()] param($Uri, $tenantid, $AsApp) }
    function Set-CIPPAuthenticationPolicy { [CmdletBinding()] param($Tenant, $APIName, $AuthenticationMethodId, [bool]$Enabled, $GroupIds, $ExcludeGroupIds, $PasswordAllowChangeAfterSecureSignIn) }
    function Write-LogMessage { [CmdletBinding()] param($API, $tenant, $message, $sev, $LogData) }
    function Write-StandardsAlert { [CmdletBinding()] param($message, $object, $tenant, $standardName, $standardId) }
    function Set-CIPPStandardsCompareField { [CmdletBinding()] param($FieldName, $CurrentValue, $ExpectedValue, $TenantFilter) }
    function Get-CippException { [CmdletBinding()] param($Exception) [PSCustomObject]@{ NormalizedError = "$Exception" } }

    . $StandardPath
    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Invoke-CIPPStandardAuthenticationMethods - Password setting' {
    BeforeEach {
        Mock New-GraphGetRequest {
            [PSCustomObject]@{ authenticationMethodConfigurations = @(
                    [PSCustomObject]@{ id = 'Sms'; state = 'enabled'; includeTargets = @([PSCustomObject]@{ id = 'all_users'; targetType = 'group' }) }
                    [PSCustomObject]@{ id = 'Password'; state = 'enabled'; allowPasswordChangeAfterSecureSignIn = $false }
                ) }
        }
        Mock Set-CIPPAuthenticationPolicy { }
        Mock Write-LogMessage { }
        Mock Write-StandardsAlert { }
        Mock Set-CIPPStandardsCompareField { }
    }

    It 'a template without the field never grades, writes or reports Password' {
        Invoke-CIPPStandardAuthenticationMethods -Tenant $script:Tenant -Settings @{ SMSEnabled = $false; remediate = $true; alert = $true; report = $true }

        Should -Invoke Set-CIPPAuthenticationPolicy -Times 1 -Exactly
        Should -Invoke Set-CIPPAuthenticationPolicy -Times 1 -Exactly -ParameterFilter { $AuthenticationMethodId -eq 'SMS' }
        Should -Invoke Write-StandardsAlert -Times 1 -Exactly -ParameterFilter { @($object).Count -eq 1 -and $object.Method -eq 'SMS' }
        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            @($CurrentValue.PSObject.Properties.Name) -join ',' -eq 'SMS' -and @($ExpectedValue.PSObject.Properties.Name) -join ',' -eq 'SMS'
        }
    }

    It 'a blank field is the same as an absent one' {
        Invoke-CIPPStandardAuthenticationMethods -Tenant $script:Tenant -Settings @{ SMSEnabled = $false; PasswordChangeAfterSecureSignIn = ''; remediate = $true; report = $true }

        Should -Invoke Set-CIPPAuthenticationPolicy -Times 1 -Exactly
        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            $null -eq $CurrentValue.PSObject.Properties['Password']
        }
    }

    It 'still skips entirely when nothing at all is configured' {
        Invoke-CIPPStandardAuthenticationMethods -Tenant $script:Tenant -Settings @{ remediate = $true; report = $true }

        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        Should -Invoke Set-CIPPAuthenticationPolicy -Times 0 -Exactly
    }

    It 'runs with only the Password field set and writes only that setting' {
        $Settings = @{ PasswordChangeAfterSecureSignIn = [PSCustomObject]@{ label = 'Enabled'; value = 'true' }; remediate = $true; report = $true }
        Invoke-CIPPStandardAuthenticationMethods -Tenant $script:Tenant -Settings $Settings

        Should -Invoke Set-CIPPAuthenticationPolicy -Times 1 -Exactly -ParameterFilter {
            $AuthenticationMethodId -eq 'Password' -and
            $PasswordAllowChangeAfterSecureSignIn -eq $true -and
            $null -eq $GroupIds -and $null -eq $ExcludeGroupIds
        }
        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            @($ExpectedValue.Password.PSObject.Properties.Name) -join ',' -eq 'allowPasswordChangeAfterSecureSignIn' -and
            $ExpectedValue.Password.allowPasswordChangeAfterSecureSignIn -eq $true -and
            $CurrentValue.Password.allowPasswordChangeAfterSecureSignIn -eq $false
        }
    }

    It 'does not write Password when the tenant already matches' {
        Invoke-CIPPStandardAuthenticationMethods -Tenant $script:Tenant -Settings @{ PasswordChangeAfterSecureSignIn = 'false'; remediate = $true; alert = $true }

        Should -Invoke Set-CIPPAuthenticationPolicy -Times 0 -Exactly
        Should -Invoke Write-StandardsAlert -Times 0 -Exactly
    }
}
