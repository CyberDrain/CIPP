# Pester tests for Get-CIPPTenantCloudEnvironment
#
# Every tenant row records the Microsoft cloud it lives in so token and endpoint routing can branch
# on it (redanthrax/CIPP#1). Detection runs while a tenant is being added, so it must never throw,
# must never build a discovery URL from unchecked input, and must fall back to Commercial.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Write-LogMessage { param($API, $tenant, $tenantid, $message, $Sev, $LogData, $headers) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPTenantCloudEnvironment.ps1')

    $script:TenantGuid = '11111111-2222-3333-4444-555555555555'

    function New-Discovery {
        param($Instance = 'microsoftonline.com', $Scope = 'NA', $SubScope)
        $Doc = [ordered]@{ cloud_instance_name = $Instance; tenant_region_scope = $Scope }
        if ($SubScope) { $Doc.tenant_region_sub_scope = $SubScope }
        [PSCustomObject]$Doc
    }
}

Describe 'Get-CIPPTenantCloudEnvironment' {
    BeforeEach {
        Mock Write-LogMessage {}
    }

    Context 'OpenID discovery' {
        It 'returns <Expected> for instance <Instance>, scope <Scope>, sub scope <SubScope>' -TestCases @(
            @{ Instance = 'microsoftonline.com'; Scope = 'NA'; SubScope = $null; Expected = 'Commercial' }
            @{ Instance = 'microsoftonline.com'; Scope = 'EU'; SubScope = $null; Expected = 'Commercial' }
            @{ Instance = 'microsoftonline.com'; Scope = 'NA'; SubScope = 'GCC'; Expected = 'Commercial' }
            @{ Instance = 'microsoftonline.us'; Scope = 'USGov'; SubScope = 'DODCON'; Expected = 'USGovHigh' }
            @{ Instance = 'microsoftonline.us'; Scope = 'USGov'; SubScope = $null; Expected = 'USGovHigh' }
            @{ Instance = 'microsoftonline.us'; Scope = 'USGov'; SubScope = 'DOD'; Expected = 'USGovDoD' }
            @{ Instance = 'microsoftonline.com'; Scope = 'USGov'; SubScope = $null; Expected = 'USGovHigh' }
        ) {
            param($Instance, $Scope, $SubScope, $Expected)
            Mock Invoke-RestMethod { New-Discovery -Instance $Instance -Scope $Scope -SubScope $SubScope }
            Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid -InitialDomainName 'contoso.onmicrosoft.com' | Should -Be $Expected
        }

        It 'queries the commercial login endpoint for the tenant' {
            Mock Invoke-RestMethod { New-Discovery }
            $null = Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid
            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter {
                $Uri -eq "https://login.microsoftonline.com/$($script:TenantGuid)/v2.0/.well-known/openid-configuration"
            }
        }

        It 'accepts a domain as tenant id' {
            Mock Invoke-RestMethod { New-Discovery -Instance 'microsoftonline.us' -Scope 'USGov' -SubScope 'DODCON' }
            Get-CIPPTenantCloudEnvironment -TenantId 'contoso.onmicrosoft.us' | Should -Be 'USGovHigh'
            Should -Invoke Invoke-RestMethod -Times 1
        }

        It 'trusts an onmicrosoft.us initial domain over a commercial discovery answer' {
            Mock Invoke-RestMethod { New-Discovery }
            Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid -InitialDomainName 'contoso.onmicrosoft.us' | Should -Be 'USGovHigh'
        }
    }

    Context 'fallback' {
        It 'falls back to Commercial and logs when discovery fails' {
            Mock Invoke-RestMethod { throw 'network down' }
            Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid -InitialDomainName 'contoso.onmicrosoft.com' | Should -Be 'Commercial'
            Should -Invoke Write-LogMessage -Times 1
        }

        It 'falls back to USGovHigh for an onmicrosoft.us initial domain when discovery fails' {
            Mock Invoke-RestMethod { throw 'network down' }
            Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid -InitialDomainName 'contoso.onmicrosoft.us' | Should -Be 'USGovHigh'
        }

        It 'returns Commercial with no input at all' {
            Mock Invoke-RestMethod { throw 'should not be called' }
            Get-CIPPTenantCloudEnvironment | Should -Be 'Commercial'
            Should -Invoke Invoke-RestMethod -Times 0
        }
    }

    Context 'input validation' {
        It 'does not call discovery for tenant id <TenantId>' -TestCases @(
            @{ TenantId = '../../evil.com/x' }
            @{ TenantId = 'contoso.com/../common' }
            @{ TenantId = 'evil.com?x=1' }
            @{ TenantId = 'evil.com#frag' }
            @{ TenantId = 'user@evil.com' }
            @{ TenantId = 'not a tenant' }
            @{ TenantId = '11111111-2222-3333-4444-55555555555' }
        ) {
            param($TenantId)
            Mock Invoke-RestMethod { New-Discovery -Instance 'microsoftonline.us' -Scope 'USGov' }
            Get-CIPPTenantCloudEnvironment -TenantId $TenantId -InitialDomainName 'contoso.onmicrosoft.com' | Should -Be 'Commercial'
            Should -Invoke Invoke-RestMethod -Times 0
        }

        It 'still uses the initial domain when the tenant id is invalid' {
            Mock Invoke-RestMethod { throw 'should not be called' }
            Get-CIPPTenantCloudEnvironment -TenantId 'bad/id' -InitialDomainName 'contoso.onmicrosoft.us' | Should -Be 'USGovHigh'
        }
    }

    Context 'unexpected discovery responses' {
        It 'returns <Expected> when discovery returns <Name>' -TestCases @(
            @{ Name = 'an empty object'; Response = [pscustomobject]@{}; Initial = 'contoso.onmicrosoft.com'; Expected = 'Commercial' }
            @{ Name = 'null'; Response = $null; Initial = 'contoso.onmicrosoft.com'; Expected = 'Commercial' }
            @{ Name = 'an HTML string'; Response = '<html>Sign in</html>'; Initial = 'contoso.onmicrosoft.com'; Expected = 'Commercial' }
            @{ Name = 'an error document'; Response = [pscustomobject]@{ error = 'invalid_tenant'; error_description = 'AADSTS90002' }; Initial = 'contoso.onmicrosoft.com'; Expected = 'Commercial' }
            @{ Name = 'an empty object for a gov initial domain'; Response = [pscustomobject]@{}; Initial = 'contoso.onmicrosoft.us'; Expected = 'USGovHigh' }
            @{ Name = 'only the sub scope DOD'; Response = [pscustomobject]@{ tenant_region_sub_scope = 'DOD' }; Initial = 'contoso.onmicrosoft.com'; Expected = 'Commercial' }
            @{ Name = 'an unknown cloud instance'; Response = [pscustomobject]@{ cloud_instance_name = 'chinacloudapi.cn'; tenant_region_scope = 'AS' }; Initial = 'contoso.partner.onmschina.cn'; Expected = 'Commercial' }
            @{ Name = 'a near-miss instance name'; Response = [pscustomobject]@{ cloud_instance_name = 'microsoftonline.us.evil.com'; tenant_region_scope = 'NA' }; Initial = 'contoso.onmicrosoft.com'; Expected = 'Commercial' }
            @{ Name = 'a numeric region scope'; Response = [pscustomobject]@{ cloud_instance_name = 'microsoftonline.com'; tenant_region_scope = 42 }; Initial = 'contoso.onmicrosoft.com'; Expected = 'Commercial' }
        ) {
            param($Name, $Response, $Initial, $Expected)
            Mock Invoke-RestMethod { $Response }
            Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid -InitialDomainName $Initial | Should -Be $Expected
        }

        It 'treats field values case-insensitively (<Instance>/<Scope>/<SubScope> -> <Expected>)' -TestCases @(
            @{ Instance = 'MicrosoftOnline.US'; Scope = 'usgov'; SubScope = 'dod'; Expected = 'USGovDoD' }
            @{ Instance = 'MICROSOFTONLINE.US'; Scope = 'USGOV'; SubScope = 'DodCon'; Expected = 'USGovHigh' }
            @{ Instance = 'microsoftonline.com'; Scope = 'UsGov'; SubScope = 'Dod'; Expected = 'USGovDoD' }
        ) {
            param($Instance, $Scope, $SubScope, $Expected)
            Mock Invoke-RestMethod { New-Discovery -Instance $Instance -Scope $Scope -SubScope $SubScope }
            Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid | Should -Be $Expected
        }

        It 'matches an upper-case onmicrosoft.us initial domain' {
            Mock Invoke-RestMethod { New-Discovery }
            Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid -InitialDomainName 'CONTOSO.ONMICROSOFT.US' | Should -Be 'USGovHigh'
        }

        It 'does not treat a look-alike initial domain as gov (<Initial>)' -TestCases @(
            @{ Initial = 'contoso.onmicrosoft.us.evil.com' }
            @{ Initial = 'contoso-onmicrosoft.us' }
            @{ Initial = 'onmicrosoft.us' }
            @{ Initial = "evil.com`ncontoso.onmicrosoft.us" }
        ) {
            param($Initial)
            Mock Invoke-RestMethod { throw 'unreachable' }
            Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid -InitialDomainName $Initial | Should -Be 'Commercial'
        }
    }

    Context 'timeouts and resilience' {
        It 'bounds the discovery call with a timeout' {
            Mock Invoke-RestMethod { New-Discovery }
            $null = Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid
            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $TimeoutSec -gt 0 -and $TimeoutSec -le 30 }
        }

        It 'falls back when discovery times out' {
            Mock Invoke-RestMethod { throw [System.Threading.Tasks.TaskCanceledException]::new('The request was canceled due to the configured HttpClient.Timeout of 15 seconds elapsing.') }
            Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid -InitialDomainName 'contoso.onmicrosoft.us' | Should -Be 'USGovHigh'
            Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid -InitialDomainName 'contoso.onmicrosoft.com' | Should -Be 'Commercial'
        }

        It 'falls back on an HTTP error from discovery' {
            Mock Invoke-RestMethod { throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Response status code does not indicate success: 400 (Bad Request).', [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]::BadRequest)) }
            Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid -InitialDomainName 'contoso.onmicrosoft.com' | Should -Be 'Commercial'
        }

        It 'does not throw when logging the fallback fails (<Case>)' -TestCases @(
            @{ Case = 'discovery failed'; TenantId = '11111111-2222-3333-4444-555555555555' }
            @{ Case = 'invalid tenant id'; TenantId = 'bad/id' }
        ) {
            param($Case, $TenantId)
            Mock Invoke-RestMethod { throw 'network down' }
            Mock Write-LogMessage { throw 'log table unavailable' }
            { Get-CIPPTenantCloudEnvironment -TenantId $TenantId -InitialDomainName 'contoso.onmicrosoft.us' } | Should -Not -Throw
            Get-CIPPTenantCloudEnvironment -TenantId $TenantId -InitialDomainName 'contoso.onmicrosoft.us' | Should -Be 'USGovHigh'
        }

        It 'returns exactly one string' {
            Mock Invoke-RestMethod { New-Discovery -Instance 'microsoftonline.us' -Scope 'USGov' -SubScope 'DOD' }
            $Result = @(Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid)
            $Result.Count | Should -Be 1
            $Result[0] | Should -BeOfType [string]
        }
    }

    Context 'url safety' {
        It 'rejects a tenant id with a trailing newline (<Name>) without calling discovery' -TestCases @(
            @{ Name = 'domain'; TenantId = "contoso.com`n" }
            @{ Name = 'guid'; TenantId = "11111111-2222-3333-4444-555555555555`n" }
            @{ Name = 'crlf'; TenantId = "contoso.com`r`n" }
        ) {
            param($Name, $TenantId)
            # .NET's $ anchor matches before a final newline; the patterns use \z so this is rejected
            Mock Invoke-RestMethod { New-Discovery -Instance 'microsoftonline.us' -Scope 'USGov' }
            Get-CIPPTenantCloudEnvironment -TenantId $TenantId -InitialDomainName 'contoso.onmicrosoft.com' | Should -Be 'Commercial'
            Should -Invoke Invoke-RestMethod -Times 0
        }

        It 'does not treat an initial domain with a trailing newline as gov' {
            Mock Invoke-RestMethod { throw 'unreachable' }
            Get-CIPPTenantCloudEnvironment -TenantId $script:TenantGuid -InitialDomainName "contoso.onmicrosoft.us`n" | Should -Be 'Commercial'
        }

        It 'only ever calls the commercial login host' {
            Mock Invoke-RestMethod { New-Discovery }
            $null = Get-CIPPTenantCloudEnvironment -TenantId 'login.microsoftonline.us'
            Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { ([uri]$Uri).Host -eq 'login.microsoftonline.com' -and ([uri]$Uri).Segments.Count -eq 5 }
        }
    }
}

