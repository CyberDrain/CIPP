# Pester tests for Invoke-ExecReactivateSite: OneDrive accounts keep the Unlicensed OneDrive billing wording, other
# SharePoint sites get plain site wording.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $AsApp, $type, $body) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }
    function Get-Tenants { param($TenantFilter) }

    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ExecReactivateSite.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    function New-TestRequest {
        param([string]$SiteUrl, [switch]$NoIds)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecReactivateSite' }
            Headers = @{}
            Body    = [pscustomobject]@{
                tenantFilter = 'contoso.onmicrosoft.com'
                SiteUrl      = $SiteUrl
                SiteId       = if ($NoIds) { $null } else { 'aaaaaaaa-0000-0000-0000-000000000001' }
                WebId        = if ($NoIds) { $null } else { 'bbbbbbbb-0000-0000-0000-000000000002' }
            }
        }
    }
}

Describe 'Invoke-ExecReactivateSite' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock New-GraphPOSTRequest { }
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'contoso.onmicrosoft.com' } }
    }

    It 'mentions Unlicensed OneDrive billing for a OneDrive account on <SiteHost>' -ForEach @(
        @{ SiteHost = 'contoso-my.sharepoint.com' }
        @{ SiteHost = 'contoso-my.sharepoint.us' }
        @{ SiteHost = 'contoso-my.sharepoint-mil.us' }
    ) {
        $Response = Invoke-ExecReactivateSite -Request (New-TestRequest "https://$SiteHost/personal/megan_contoso_com")

        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $Response.Body.Results | Should -BeLike '*up to 24 hours*Unlicensed OneDrive billing*'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $uri -eq "https://graph.microsoft.com/beta/sites/$SiteHost,aaaaaaaa-0000-0000-0000-000000000001,bbbbbbbb-0000-0000-0000-000000000002/unarchive"
        }
    }

    It 'returns NotFound for a tenant CIPP does not manage, without calling Microsoft Graph' {
        Mock Get-Tenants { }

        $Response = Invoke-ExecReactivateSite -Request (New-TestRequest 'https://contoso.sharepoint.com/sites/OldProjects')

        $Response.StatusCode | Should -Be ([HttpStatusCode]::NotFound)
        $Response.Body.Results | Should -BeLike "*does not manage the tenant 'contoso.onmicrosoft.com'*"
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'returns NotFound when the site id cannot be determined' {
        Mock New-GraphGetRequest { }

        $Response = Invoke-ExecReactivateSite -Request (New-TestRequest 'https://contoso.sharepoint.com/sites/Gone' -NoIds)

        $Response.StatusCode | Should -Be ([HttpStatusCode]::NotFound)
        $Response.Body.Results | Should -BeLike '*Could not determine the site id*'
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'uses plain site wording for a SharePoint site' {
        $Response = Invoke-ExecReactivateSite -Request (New-TestRequest 'https://contoso.sharepoint.com/sites/OldProjects')

        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $Response.Body.Results | Should -Be 'Reactivation started for https://contoso.sharepoint.com/sites/OldProjects. It can take up to 24 hours before the site can be opened again.'
    }

    It 'points <Kind> to the SharePoint admin center when the request is blocked' -ForEach @(
        @{ Kind = 'a OneDrive account'; Url = 'https://contoso-my.sharepoint.com/personal/megan_contoso_com'; Expected = '*Unlicensed OneDrive billing*SharePoint admin center*' }
        @{ Kind = 'a GCC High OneDrive account'; Url = 'https://contoso-my.sharepoint.us/personal/megan_contoso_com'; Expected = '*Unlicensed OneDrive billing*SharePoint admin center*' }
        @{ Kind = 'a SharePoint site'; Url = 'https://contoso.sharepoint.com/sites/OldProjects'; Expected = '*cannot be reactivated through CIPP right now. Reactivate it from the SharePoint admin center.' }
    ) {
        Mock New-GraphPOSTRequest { throw 'The site is locked (423).' }

        $Response = Invoke-ExecReactivateSite -Request (New-TestRequest $Url)

        $Response.StatusCode | Should -Be ([HttpStatusCode]::InternalServerError)
        $Response.Body.Results | Should -BeLike $Expected
        if ($Kind -eq 'a SharePoint site') { $Response.Body.Results | Should -Not -BeLike '*OneDrive*' }
    }
}
