# Pester tests for Invoke-ExecRemoveSPOExternalUser
# Covers that only userType Guest accounts are deleted and that a member account with nothing to remove is refused.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecRemoveSPOExternalUser.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecRemoveSPOExternalUser.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippException { param($Exception) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $asapp) }
    function Remove-CIPPSPOSiteUser { param($TenantFilter, $SiteUrls, $LoginName) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev, $LogData) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')

    . $FunctionPath
}

Describe 'Invoke-ExecRemoveSPOExternalUser' {
    BeforeEach {
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-GraphPostRequest -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ userPrincipalName = 'ext_fabrikam.com#EXT#@contoso.onmicrosoft.com'; userType = 'Guest' } }
        Mock -CommandName Remove-CIPPSPOSiteUser -MockWith { [pscustomobject]@{ Succeeded = @($SiteUrls); Failed = @() } }
    }

    It 'reports the full removal when the Entra account was deleted too' {
        $Request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ExecRemoveSPOExternalUser' }; Headers = @{}
            Body   = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; EntraUserId = 'guest-1'; LoginName = 'i:0#.f|membership|ext#ext#@contoso.onmicrosoft.com'; SiteUrls = @('https://contoso.sharepoint.com/sites/a'); DisplayName = 'Ext' }
        }

        $Response = Invoke-ExecRemoveSPOExternalUser -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -BeLike 'Removed guest access for Ext:*Deleted the Entra guest account*'
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/users/guest-1' -and $type -eq 'DELETE' }
    }

    It 'removes site access but keeps the Entra account of a member-type external user' {
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ userPrincipalName = 'ext_fabrikam.com#EXT#@contoso.onmicrosoft.com'; userType = 'Member' } }
        $Request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ExecRemoveSPOExternalUser' }; Headers = @{}
            Body   = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; EntraUserId = 'member-1'; SiteUrls = @('https://contoso.sharepoint.com/sites/a'); DisplayName = 'Synced' }
        }

        $Response = Invoke-ExecRemoveSPOExternalUser -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -BeLike 'Removed site access for Synced: Removed from 1 site(s)*The Entra account was not deleted: it is a member account*'
        Should -Invoke Remove-CIPPSPOSiteUser -Times 1 -Exactly -ParameterFilter { $LoginName -like '*#EXT#*' }
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
    }

    It 'returns 400 for a member-type external user with no sites, since nothing is removed' {
        Mock -CommandName New-GraphGetRequest -MockWith { [pscustomobject]@{ userPrincipalName = 'ext_fabrikam.com#EXT#@contoso.onmicrosoft.com'; userType = 'Member' } }
        $Request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ExecRemoveSPOExternalUser' }; Headers = @{}
            Body   = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; EntraUserId = 'member-1'; SiteUrls = @(); DisplayName = 'Synced' }
        }

        $Response = Invoke-ExecRemoveSPOExternalUser -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -BeLike 'Nothing to remove for Synced:*member account*'
        Should -Invoke Remove-CIPPSPOSiteUser -Times 0 -Exactly
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
    }

    It 'does not delete the Entra account when its type cannot be read' {
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Forbidden' }
        $Request = [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ExecRemoveSPOExternalUser' }; Headers = @{}
            Body   = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; EntraUserId = 'guest-1'; LoginName = 'i:0#.f|membership|ext#ext#@contoso.onmicrosoft.com'; SiteUrls = @('https://contoso.sharepoint.com/sites/a'); DisplayName = 'Ext' }
        }

        $Response = Invoke-ExecRemoveSPOExternalUser -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::MultiStatus)
        $Response.Body.Results | Should -BeLike 'Removed guest access for Ext: Removed from 1 site(s)*Could not read the Entra account, so it was not deleted*'
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
    }
}
