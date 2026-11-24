# Pester tests for Invoke-ListSharePointExternalUsers
# Covers the Entra join for #EXT# users of userType Member and the warnings for unreadable sources.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListSharePointExternalUsers.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListSharePointExternalUsers.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPSPOExternalUsers { param($TenantFilter) }
    function Get-SharePointAdminLink { param($Public, $tenantFilter) }
    function Get-CippException { param($Exception) }
    function New-GraphGetRequest { param($uri, $tenantid, $scope, $extraHeaders, [switch]$UseCertificate, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $scope, $AsApp, [switch]$UseCertificate, $type, $body, $contentType, $AddedHeaders) }

    . $FunctionPath
}

Describe 'Invoke-ListSharePointExternalUsers' {
    BeforeEach {
        $script:Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListSharePointExternalUsers' }; Headers = @{}; Query = @{ tenantFilter = 'contoso.onmicrosoft.com' } }
        Mock -CommandName Get-CippException -MockWith { [pscustomobject]@{ NormalizedError = $Exception.Exception.Message } }
        Mock -CommandName Get-CIPPSPOExternalUsers -MockWith { }
        Mock -CommandName Get-SharePointAdminLink -MockWith { [pscustomobject]@{ SharePointUrl = 'https://contoso.sharepoint.com' } }
        Mock -CommandName New-GraphPOSTRequest -MockWith { [pscustomobject]@{ value = @() } }
        Mock -CommandName New-GraphGetRequest -MockWith { @([pscustomobject]@{ webUrl = 'https://contoso.sharepoint.com/sites/a' }) } -ParameterFilter { $uri -like '*getAllSites*' }
        Mock -CommandName New-GraphGetRequest -MockWith {
            @([pscustomobject]@{ Id = 5; Title = 'Ext'; Email = 'ext@fabrikam.com'; LoginName = 'i:0#.f|membership|ext_fabrikam.com#ext#@contoso.onmicrosoft.com'; IsShareByEmailGuestUser = $false; IsEmailAuthenticationGuestUser = $false })
        } -ParameterFilter { $uri -like '*/_api/web/siteusers*' }
        Mock -CommandName New-GraphGetRequest -MockWith { @() } -ParameterFilter { $uri -like "*userType eq 'Guest'*" }
        Mock -CommandName New-GraphGetRequest -MockWith {
            @(
                [pscustomobject]@{ id = 'member-1'; userPrincipalName = 'ext_fabrikam.com#EXT#@contoso.onmicrosoft.com'; mail = 'ext@fabrikam.com' }
                [pscustomobject]@{ id = 'internal-1'; userPrincipalName = 'bob@contoso.com'; mail = 'bob@contoso.com' }
            )
        } -ParameterFilter { $uri -like "*userType eq 'Member'*" }
    }

    It 'matches an #EXT# user whose userType is Member instead of calling them orphaned' {
        $Response = Invoke-ListSharePointExternalUsers -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        $Row = @($Response.Body.Results)[0]
        $Row.GuestType | Should -Be 'Entra B2B'
        $Row.InEntra | Should -BeTrue
        $Row.EntraUserId | Should -Be 'member-1'
    }

    It 'skips the member sweep when every entry matched an Entra guest' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            @([pscustomobject]@{ id = 'guest-1'; userPrincipalName = 'ext_fabrikam.com#EXT#@contoso.onmicrosoft.com'; mail = 'ext@fabrikam.com' })
        } -ParameterFilter { $uri -like "*userType eq 'Guest'*" }

        $Response = Invoke-ListSharePointExternalUsers -Request $Request -TriggerMetadata $null

        @($Response.Body.Results)[0].EntraUserId | Should -Be 'guest-1'
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like "*userType eq 'Member'*" }
    }

    It 'returns MultiStatus with a warning when a site user list cannot be read' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            @([pscustomobject]@{ webUrl = 'https://contoso.sharepoint.com/sites/a' }, [pscustomobject]@{ webUrl = 'https://contoso.sharepoint.com/sites/locked' })
        } -ParameterFilter { $uri -like '*getAllSites*' }
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Access denied' } -ParameterFilter { $uri -like '*/sites/locked/_api/web/siteusers*' }

        $Response = Invoke-ListSharePointExternalUsers -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::MultiStatus)
        @($Response.Body.Results).Count | Should -Be 1
        @($Response.Body.Metadata.Warnings).Count | Should -Be 1
        $Response.Body.Metadata.Warnings[0] | Should -BeLike '*1 site(s)*https://contoso.sharepoint.com/sites/locked*'
    }

    It 'returns MultiStatus with a warning when sites cannot be enumerated' {
        Mock -CommandName New-GraphGetRequest -MockWith { throw 'Forbidden' } -ParameterFilter { $uri -like '*getAllSites*' }
        Mock -CommandName Get-CIPPSPOExternalUsers -MockWith { [pscustomobject]@{ DisplayName = 'Store'; AcceptedAs = 'store@fabrikam.com' } }

        $Response = Invoke-ListSharePointExternalUsers -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::MultiStatus)
        @($Response.Body.Results).Count | Should -Be 1
        $Response.Body.Metadata.Warnings[0] | Should -BeLike 'Could not enumerate SharePoint sites*Forbidden'
    }

    It 'returns OK with no warnings when every source was read' {
        Mock -CommandName New-GraphGetRequest -MockWith {
            @([pscustomobject]@{ id = 'guest-1'; userPrincipalName = 'ext_fabrikam.com#EXT#@contoso.onmicrosoft.com'; mail = 'ext@fabrikam.com' })
        } -ParameterFilter { $uri -like "*userType eq 'Guest'*" }

        $Response = Invoke-ListSharePointExternalUsers -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        @($Response.Body.Metadata.Warnings).Count | Should -Be 0
    }
}
