# Max credential end date allowed by the tenant default app management policy's passwordLifetime
# restriction, or $null when not enforced/readable. Custom per-app policies aren't read here.
function Get-CIPPAppPasswordPolicyMaxEnd {
    <#
    .NOTES
        Permission: Graph | GET /policies/defaultAppManagementPolicy | Application | Policy.Read.All | Policy.ReadWrite.ApplicationConfiguration
    #>
    param([datetime]$From, $TenantFilter, $APIName, $Headers)
    try {
        $Policy = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/defaultAppManagementPolicy' -tenantid $TenantFilter -AsApp $true
        $Lifetime = $Policy.applicationRestrictions.passwordCredentials | Where-Object { $_.restrictionType -eq 'passwordLifetime' }
        if ($Lifetime -and -not ($Lifetime.state -eq 'disabled' -or $null -eq $Lifetime.state) -and $Lifetime.maxLifetime) {
            return $From.Add([System.Xml.XmlConvert]::ToTimeSpan($Lifetime.maxLifetime))
        }
    } catch {
        Write-LogMessage -API $APIName -tenant $TenantFilter -headers $Headers -message "Could not read app management policy for expiry clamping: $($_.Exception.Message)" -sev Debug
    }
    return $null
}
