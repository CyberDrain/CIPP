# Pester tests for the Microsoft 365 Archive endpoints: Invoke-ListSharePointArchiveSettings,
# and Invoke-ExecArchiveSite.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Endpoints = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint'
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPDbItem { [CmdletBinding()] param($TenantFilter, $Type, $TableName, [switch]$CountsOnly) }
    function New-CIPPDbRequest { [CmdletBinding()] param($TenantFilter, $Type, $TableName) }
    function Get-Tenants { param($TenantFilter) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $AsApp, $type, $body) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }

    . (Join-Path $Endpoints 'Invoke-ListSharePointArchiveSettings.ps1')
    . (Join-Path $Endpoints 'Invoke-ExecArchiveSite.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    function New-GetRequest {
        param([string]$Endpoint, [hashtable]$Query = @{})
        [pscustomobject]@{ Params = @{ CIPPEndpoint = $Endpoint }; Headers = @{}; Query = [pscustomobject]$Query }
    }
    function New-PostRequest {
        param([hashtable]$Body)
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecArchiveSite' }; Headers = @{}; Body = [pscustomobject]$Body }
    }
}

Describe 'Invoke-ListSharePointArchiveSettings' {
    It 'returns BadRequest without a tenantFilter' {
        $Response = Invoke-ListSharePointArchiveSettings -Request (New-GetRequest 'ListSharePointArchiveSettings')
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }

    It 'returns BadRequest for AllTenants' {
        Mock Get-CIPPDbItem { }

        $Response = Invoke-ListSharePointArchiveSettings -Request (New-GetRequest 'ListSharePointArchiveSettings' @{ tenantFilter = 'AllTenants' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -BeLike '*one tenant at a time*'
        Should -Invoke Get-CIPPDbItem -Times 0 -Exactly
    }

    It 'returns NotFound when the tenant configuration has never been collected' {
        Mock Get-CIPPDbItem { [pscustomobject]@{ RowKey = 'SPOTenant-Count'; Data = '' } }

        $Response = Invoke-ListSharePointArchiveSettings -Request (New-GetRequest 'ListSharePointArchiveSettings' @{ tenantFilter = 'contoso.com' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
    }

    It 'reports the archive switches, archived storage and quota from the cached configuration' {
        Mock Get-CIPPDbItem {
            [pscustomobject]@{ RowKey = 'SPOTenant-Count'; Data = '' }
            [pscustomobject]@{
                RowKey    = 'SPOTenant-1'
                Timestamp = [datetimeoffset]'2026-11-21T23:00:00Z'
                Data      = '{"EnableSiteArchive":true,"AllowFileArchive":false,"AllowFileArchiveOnNewSitesByDefault":true,"ArchivedFileStorageUsageMB":2048,"StorageQuota":1191936}'
            }
        }

        $Response = Invoke-ListSharePointArchiveSettings -Request (New-GetRequest 'ListSharePointArchiveSettings' @{ tenantFilter = 'contoso.com' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Row = @($Response.Body)[0]
        $Row.archiveEnabled | Should -BeTrue
        $Row.allowFileArchive | Should -BeFalse
        $Row.allowFileArchiveOnNewSites | Should -BeTrue
        $Row.archivedFileStorageInBytes | Should -Be (2048 * 1MB)
        $Row.storageQuotaInBytes | Should -Be (1191936 * 1MB)
    }

    It 'treats a tenant without the archive properties as not enabled' {
        Mock Get-CIPPDbItem { [pscustomobject]@{ RowKey = 'SPOTenant-1'; Data = '{"StorageQuota":1024}' } }

        $Response = Invoke-ListSharePointArchiveSettings -Request (New-GetRequest 'ListSharePointArchiveSettings' @{ tenantFilter = 'contoso.com' })

        @($Response.Body)[0].archiveEnabled | Should -BeFalse
        @($Response.Body)[0].archivedFileStorageInBytes | Should -Be 0
    }
}

Describe 'Invoke-ExecArchiveSite' {
    BeforeEach {
        Mock New-GraphPOSTRequest { }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'contoso.sharepoint.com,resolved-site,resolved-web' } }
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'contoso.com' } }
        Mock Write-LogMessage { }
    }

    It 'returns BadRequest for <Name>' -ForEach @(
        @{ Name = 'a missing tenantFilter'; Body = @{ SiteUrl = 'https://contoso.sharepoint.com/sites/Old' } }
        @{ Name = 'a missing SiteUrl'; Body = @{ tenantFilter = 'contoso.com' } }
        @{ Name = 'a SiteUrl that is not a URL'; Body = @{ tenantFilter = 'contoso.com'; SiteUrl = 'Old Projects' } }
    ) {
        $Response = Invoke-ExecArchiveSite -Request (New-PostRequest -Body $Body)

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'returns NotFound for a tenant CIPP does not manage' {
        Mock Get-Tenants { }

        $Response = Invoke-ExecArchiveSite -Request (New-PostRequest -Body @{ tenantFilter = 'unknown.example'; SiteUrl = 'https://contoso.sharepoint.com/sites/Old' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'archives by the ids the site listing already carries' {
        $Response = Invoke-ExecArchiveSite -Request (New-PostRequest -Body @{
                tenantFilter = 'contoso.com'
                SiteUrl      = 'https://contoso.sharepoint.com/sites/Old'
                SiteId       = '{aaaaaaaa-0000-0000-0000-000000000001}'
                WebId        = 'bbbbbbbb-0000-0000-0000-000000000002'
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -BeLike '*up to 24 hours*'
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -eq 'https://graph.microsoft.com/beta/sites/contoso.sharepoint.com,aaaaaaaa-0000-0000-0000-000000000001,bbbbbbbb-0000-0000-0000-000000000002/archive' -and $AsApp -eq $true
        }
    }

    It 'looks the site up by its address when the ids are missing or malformed' {
        $Response = Invoke-ExecArchiveSite -Request (New-PostRequest -Body @{ tenantFilter = 'contoso.com'; SiteUrl = 'https://contoso.sharepoint.com/sites/Old/'; SiteId = 'x/../y' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like 'https://graph.microsoft.com/v1.0/sites/contoso.sharepoint.com:/sites/Old?*' }
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/sites/contoso.sharepoint.com,resolved-site,resolved-web/archive' }
    }

    It 'returns NotFound when the site cannot be found' {
        Mock New-GraphGetRequest { }

        $Response = Invoke-ExecArchiveSite -Request (New-PostRequest -Body @{ tenantFilter = 'contoso.com'; SiteUrl = 'https://contoso.sharepoint.com/sites/Gone' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::NotFound)
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'returns InternalServerError when Microsoft Graph refuses the archive' {
        Mock New-GraphPOSTRequest { throw 'The group connected site with channel sites associated cannot be archived.' }

        $Response = Invoke-ExecArchiveSite -Request (New-PostRequest -Body @{ tenantFilter = 'contoso.com'; SiteUrl = 'https://contoso.sharepoint.com/sites/Old' })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        $Response.Body.Results | Should -BeLike 'Failed to archive https://contoso.sharepoint.com/sites/Old:*'
    }
}

