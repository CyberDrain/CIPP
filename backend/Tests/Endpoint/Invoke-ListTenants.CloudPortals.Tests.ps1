# The tenant list's portal_* columns (Mode=TenantList) follow a government tenant's cloud (redanthrax/CIPP#4);
# a Commercial tenant's columns are exactly as before.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListTenants.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Test-CIPPAccess { param($Request, [switch]$TenantList) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors, [switch]$SkipDomains, [switch]$TriggerRefresh) }
    function Get-TenantGroups { @() }
    function Get-CIPPSharePointDomain { param($TenantDomain) }
    function Write-LogMessage { param($headers, $tenant, $API, $message, $Sev) }
    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/ConvertTo-CIPPCloudPortalUrl.ps1')
    $script:PreviousRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $RepoRoot
}

AfterAll { $env:CIPPRootPath = $script:PreviousRoot }

Describe 'Invoke-ListTenants portal columns' {
    BeforeEach {
        Mock Test-CIPPAccess { @('AllTenants') }
        Mock Write-LogMessage {}
        Mock Get-Tenants {
            @(
                [pscustomobject]@{ customerId = 'c1'; defaultDomainName = 'contoso.com'; initialDomainName = 'contoso.onmicrosoft.com'; displayName = 'Contoso'; cloudEnvironment = 'Commercial' }
                [pscustomobject]@{ customerId = 'g1'; defaultDomainName = 'gov.us'; initialDomainName = 'gov.onmicrosoft.us'; displayName = 'Gov'; cloudEnvironment = 'USGovHigh' }
            )
        }
    }

    It 'keeps a Commercial tenant''s portal links and re-points a GCC High tenant''s' {
        $Body = (Invoke-ListTenants -Request ([pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListTenants' }; Headers = @{}; Query = [pscustomobject]@{ Mode = 'TenantList' }; Body = $null })).Body
        $Com = $Body | Where-Object customerId -EQ 'c1'
        $Gov = $Body | Where-Object customerId -EQ 'g1'

        $Com.portal_m365 | Should -BeExactly 'https://admin.cloud.microsoft/?delegatedOrg=contoso.onmicrosoft.com'
        $Com.portal_entra | Should -BeExactly 'https://entra.microsoft.com/contoso.com'
        $Com.portal_security | Should -BeExactly 'https://security.microsoft.com/?tid=c1'
        $Com.portal_teams | Should -BeExactly 'https://admin.teams.microsoft.com?delegatedOrg=contoso.onmicrosoft.com'
        $Com.portal_bi | Should -BeExactly 'https://app.powerbi.com/admin-portal?ctid=c1'

        $Gov.portal_entra | Should -BeExactly 'https://entra.microsoft.us/gov.us'
        $Gov.portal_azure | Should -BeExactly 'https://portal.azure.us/gov.us'
        $Gov.portal_intune | Should -BeExactly 'https://intune.microsoft.us/gov.us'
        $Gov.portal_security | Should -BeExactly 'https://security.microsoft.us/?tid=g1'
        $Gov.portal_platform | Should -BeExactly 'https://high.admin.powerplatform.microsoft.us/account/login/g1'
        $Gov.portal_compliance | Should -BeExactly 'https://purview.microsoft.us/?tid=g1'
        foreach ($Name in 'portal_m365', 'portal_exchange', 'portal_teams', 'portal_bi') { $Gov.$Name | Should -BeNullOrEmpty -Because $Name }
        $Gov.portal_sharepoint | Should -BeExactly '/api/ListSharePointAdminUrl?tenantFilter=gov.us'
    }
}
