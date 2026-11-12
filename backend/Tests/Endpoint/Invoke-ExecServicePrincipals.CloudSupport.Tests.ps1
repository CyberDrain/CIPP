# Invoke-ExecServicePrincipals reads the partner tenant's service principals. For an app in a government
# tenant the app registration permissions view passes that tenant, because its permission ids differ
# (redanthrax/CIPP#4). The tenant is used only for reads, only when it is in a non-Commercial cloud and
# only when the caller may access it. Every other request is answered from the partner tenant, as before.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecServicePrincipals.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function New-GraphGetRequest { param($Uri, $tenantid, $NoAuthCheck, [switch]$ComplexFilter) }
    function New-GraphPostRequest { param($Uri, $tenantid, $type, $body, $NoAuthCheck) }
    function Get-CIPPTenantRequestCloud { param($TenantFilter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    function Test-CIPPAccess { param($Request, [switch]$TenantList) }
    function Get-Tenants { param($TenantFilter) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    . $FunctionPath

    $script:Partner = '11111111-2222-3333-4444-555555555555'
    function script:New-SPRequest { param([hashtable]$Query) [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecServicePrincipals' }; Headers = @{}; Query = [pscustomobject]$Query } }
}

Describe 'Invoke-ExecServicePrincipals tenant selection' {
    BeforeEach {
        $script:SavedTenantId = $env:TenantID
        $env:TenantID = $script:Partner
        Mock New-GraphGetRequest { @([pscustomobject]@{ appId = 'x'; id = 'y' }) }
        Mock New-GraphPostRequest { [pscustomobject]@{ displayName = 'App'; appId = $null } }
        Mock Get-CIPPTenantRequestCloud { if ($TenantFilter -like '*.us') { 'USGovHigh' } else { 'Commercial' } }
        Mock Test-CIPPAccess { @('AllTenants') }
        Mock Get-Tenants { @() }
        Mock Write-LogMessage {}
    }
    AfterEach { $env:TenantID = $script:SavedTenantId }

    It 'lists the partner tenant''s service principals without a tenantFilter, with no cloud or access lookup' {
        $null = Invoke-ExecServicePrincipals -Request (script:New-SPRequest @{ Select = 'appId,displayName,id' })
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq $script:Partner }
        Should -Invoke Get-CIPPTenantRequestCloud -Times 0 -Exactly
        Should -Invoke Test-CIPPAccess -Times 0 -Exactly
    }

    It 'ignores the usual tenantFilter, with no cloud or access lookup: <Name>' -TestCases @(
        @{ Name = 'Commercial'; Tenant = 'contoso.onmicrosoft.com' }
        @{ Name = 'AllTenants'; Tenant = 'AllTenants' }
        @{ Name = 'government (e.g. a tenant-scoped autocomplete)'; Tenant = 'gov.onmicrosoft.us' }
    ) {
        param($Name, $Tenant)
        $null = Invoke-ExecServicePrincipals -Request (script:New-SPRequest @{ Select = 'appId'; tenantFilter = $Tenant })
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq $script:Partner }
        Should -Invoke Get-CIPPTenantRequestCloud -Times 0 -Exactly
        Should -Invoke Test-CIPPAccess -Times 0 -Exactly
    }

    It 'answers a Commercial or AllTenants GovernmentTenantFilter from the partner tenant: <Tenant>' -TestCases @(
        @{ Tenant = 'contoso.onmicrosoft.com' }
        @{ Tenant = 'AllTenants' }
    ) {
        param($Tenant)
        $null = Invoke-ExecServicePrincipals -Request (script:New-SPRequest @{ Select = 'appId'; GovernmentTenantFilter = $Tenant })
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq $script:Partner }
        Should -Invoke Test-CIPPAccess -Times 0 -Exactly
    }

    It 'reads a government tenant''s service principals for <Name>' -TestCases @(
        @{ Name = 'the list'; Query = @{ Select = 'appId'; GovernmentTenantFilter = 'gov.onmicrosoft.us' } }
        @{ Name = 'one by object id'; Query = @{ Id = '11111111-2222-3333-4444-555555555555'; GovernmentTenantFilter = 'gov.onmicrosoft.us' } }
        @{ Name = 'one by appId'; Query = @{ AppId = '00000003-0000-0000-c000-000000000000'; GovernmentTenantFilter = 'gov.onmicrosoft.us' } }
    ) {
        param($Name, $Query)
        $null = Invoke-ExecServicePrincipals -Request (script:New-SPRequest $Query)
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'gov.onmicrosoft.us' }
    }

    It 'reads a government tenant for a restricted caller who may access it' {
        Mock Test-CIPPAccess { @('gov-id') }
        Mock Get-Tenants { [pscustomobject]@{ defaultDomainName = 'gov.onmicrosoft.us' } }
        $null = Invoke-ExecServicePrincipals -Request (script:New-SPRequest @{ Select = 'appId'; GovernmentTenantFilter = 'gov.onmicrosoft.us' })
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'gov.onmicrosoft.us' }
    }

    It 'falls back to the partner tenant for a caller who may not access the government tenant' {
        Mock Test-CIPPAccess { @('other-id') }
        $null = Invoke-ExecServicePrincipals -Request (script:New-SPRequest @{ Select = 'appId'; GovernmentTenantFilter = 'gov.onmicrosoft.us' })
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq $script:Partner }
    }

    It 'falls back to the partner tenant when the cloud lookup fails' {
        Mock Get-CIPPTenantRequestCloud { throw 'Unknown cloud environment' }
        $null = Invoke-ExecServicePrincipals -Request (script:New-SPRequest @{ Select = 'appId'; GovernmentTenantFilter = 'gov.onmicrosoft.us' })
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq $script:Partner }
    }

    It 'always creates service principals in the partner tenant' {
        $null = Invoke-ExecServicePrincipals -Request (script:New-SPRequest @{ Action = 'Create'; AppId = '00000003-0000-0000-c000-000000000000'; GovernmentTenantFilter = 'gov.onmicrosoft.us' })
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $tenantid -eq $script:Partner }
        Should -Invoke Get-CIPPTenantRequestCloud -Times 0 -Exactly
    }
}
