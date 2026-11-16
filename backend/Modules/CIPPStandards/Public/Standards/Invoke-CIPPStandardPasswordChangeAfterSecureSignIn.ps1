function Invoke-CIPPStandardPasswordChangeAfterSecureSignIn {
    <#
    .FUNCTIONALITY
        Internal
    .COMPONENT
        (APIName) PasswordChangeAfterSecureSignIn
    .SYNOPSIS
        (Label) Allow password change after secure sign-in (Preview)
    .DESCRIPTION
        (Helptext) Sets whether users can change their password from My Sign-Ins without entering their current password after signing in with a strong authentication method. Microsoft preview feature (MC1437671), requires Entra ID P1.
        (DocsDescription) Sets allowPasswordChangeAfterSecureSignIn on the Password configuration of the authentication methods policy. When enabled, a user who signed in with a strong authentication method can set a new password from My Sign-Ins without supplying the current one. The feature is a Microsoft preview (MC1437671) that requires Entra ID P1 and has no effect until Microsoft has rolled it out to the tenant. The state of the Password method itself is never changed.
    .NOTES
        CAT
            Entra (AAD) Standards
        TAG
        EXECUTIVETEXT
            Controls whether employees who have proven their identity with a strong sign-in method, such as a passkey or the Authenticator app, may replace their password without knowing the current one. Enabling it supports passwordless adoption and reduces helpdesk password resets, while disabling it keeps the current password as a requirement for every password change.
        ADDEDCOMPONENT
            {"type":"autoComplete","multiple":false,"creatable":false,"required":true,"name":"standards.PasswordChangeAfterSecureSignIn.state","label":"Password change after secure sign-in","options":[{"label":"Enabled","value":"true"},{"label":"Disabled","value":"false"}]}
        IMPACT
            Low Impact
        ADDEDDATE
            2026-11-16
        POWERSHELLEQUIVALENT
            Update-MgBetaPolicyAuthenticationMethodPolicyAuthenticationMethodConfiguration
        RECOMMENDEDBY
        UPDATECOMMENTBLOCK
            Run the Tools\Update-StandardsComments.ps1 script to update this comment block
    .LINK
        https://docs.cipp.app/user-documentation/tenant/standards/alignment/templates/available-standards
    #>

    param($Tenant, $Settings)

    $StateValue = "$($Settings.state.value ?? $Settings.state)"
    if ($StateValue -notin @('true', 'false')) {
        if ($Settings.remediate -eq $true -or $Settings.alert -eq $true) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message 'PasswordChangeAfterSecureSignIn: Invalid state parameter set' -sev Error
        }
        return
    }
    $DesiredState = [System.Convert]::ToBoolean($StateValue)

    try {
        $CurrentInfo = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/authenticationMethodsPolicy/authenticationMethodConfigurations/Password' -tenantid $Tenant -AsApp $true
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Standards' -tenant $Tenant -message "Could not get the PasswordChangeAfterSecureSignIn state for $Tenant. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return
    }

    # Absent (feature not rolled out to the tenant yet) reads as the Microsoft default, false.
    $CurrentState = [bool]$CurrentInfo.allowPasswordChangeAfterSecureSignIn
    $StateIsCorrect = $CurrentState -eq $DesiredState

    if ($Settings.remediate -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Password change after secure sign-in is already set to $DesiredState." -sev Info
        } else {
            try {
                # Enabled is mandatory on the helper but never written for the Password method.
                $null = Set-CIPPAuthenticationPolicy -Tenant $Tenant -APIName 'Standards' -AuthenticationMethodId 'Password' -Enabled $true -PasswordAllowChangeAfterSecureSignIn $DesiredState
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'Standards' -tenant $Tenant -message "Failed to set password change after secure sign-in to $DesiredState. Error: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
            }
        }
    }

    if ($Settings.alert -eq $true) {
        if ($StateIsCorrect) {
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Password change after secure sign-in is set to $DesiredState." -sev Info
        } else {
            Write-StandardsAlert -message "Password change after secure sign-in is not set to $DesiredState" -object ($CurrentInfo | Select-Object id, state, allowPasswordChangeAfterSecureSignIn) -tenant $Tenant -standardName 'PasswordChangeAfterSecureSignIn' -standardId $Settings.standardId
            Write-LogMessage -API 'Standards' -tenant $Tenant -message "Password change after secure sign-in is not set to $DesiredState." -sev Info
        }
    }

    if ($Settings.report -eq $true) {
        $CurrentValue = [PSCustomObject]@{ allowPasswordChangeAfterSecureSignIn = $CurrentState }
        $ExpectedValue = [PSCustomObject]@{ allowPasswordChangeAfterSecureSignIn = $DesiredState }
        Set-CIPPStandardsCompareField -FieldName 'standards.PasswordChangeAfterSecureSignIn' -CurrentValue $CurrentValue -ExpectedValue $ExpectedValue -TenantFilter $Tenant
    }
}
