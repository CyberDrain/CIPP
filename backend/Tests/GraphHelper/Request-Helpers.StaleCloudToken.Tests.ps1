# A token and the host it is sent to always agree on the cloud (redanthrax/CIPP#3).
# The request helpers ask Get-GraphToken first and Get-CIPPTenantRequestCloud second. A worker can
# still hold a commercial token for a tenant whose cloud was changed to a government one in another
# worker: Get-GraphToken's fast path returns it from the commercial cache key, and once this worker's
# cloud marker has expired the request cloud is read from the table, so the request goes to the
# government host. The helpers then fetch the token again for exactly that cloud (-RequireCloud).
# Real Get-GraphToken, Get-CIPPTenantRequestCloud and helpers; only storage and HTTP are mocked.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    if (-not ('CIPP.CIPPTokenCache' -as [type])) {
        Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    }

    function Get-CIPPAuthentication { $true }
    function Get-CippTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Update-AzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-CIPPSAMCertificate { param($Name, [switch]$SkipCache) }
    function New-CIPPCertificateAssertion { param($TenantId, $AppId, $Certificate, $Audience) }
    function Invoke-CIPPRestMethod { param($Method, $Uri, $Body, $ContentType, $Headers, $ResponseHeadersVariable, $StatusCodeVariable, [switch]$SkipHttpErrorCheck, $MaximumRedirection, $TimeoutSec) }
    function Get-CippKeyVaultName {}
    function Get-CippKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
    function Update-CIPPSAMCertificateEnvCache { param($Name, $PfxBase64) }
    function Get-CIPPGovAppCredential { param([switch]$Force) }
    function Get-AuthorisedRequest { param($Uri, $TenantID) $true }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) $Text }
    function Get-CippUserAgent { param([switch]$SharePoint) 'CIPP-test' }
    function Get-Tenants { param([switch]$IncludeErrors, $TenantFilter) [pscustomobject]@{ customerId = $script:GovTenant; defaultDomainName = 'gov.us' } }

    foreach ($File in 'Get-GraphToken', 'Get-GraphTokenFromCert', 'Get-CIPPCloudEndpoint', 'ConvertTo-CIPPCloudScope', 'ConvertTo-CIPPCloudUri',
        'Resolve-CIPPCloudHost', 'Get-CIPPPartnerCloudEnvironment', 'Get-CIPPCloudTokenRoute', 'Get-CIPPTenantRequestCloud',
        'New-GraphGetRequest', 'New-GraphPOSTRequest', 'New-GraphBulkRequest', 'New-ExoRequest', 'New-ExoBulkRequest', 'New-GraphMultiTenantBulkRequest') {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/GraphHelper/$File.ps1")
    }

    $script:Partner = '11111111-2222-3333-4444-555555555555'
    $script:GovTenant = 'a0000000-0000-0000-0000-00000000000a'
    $script:ComTenant = 'c0000000-0000-0000-0000-00000000000c'
    $script:GovAppId = '9a9a9a9a-0000-0000-0000-000000000000'
    $script:EnvNames = 'CertificateAuthMode', 'ApplicationID', 'ApplicationSecret', 'TenantID', 'RefreshToken', 'SetFromProfile', 'CIPPCredentialVersion', 'CIPP_PARTNER_CLOUD', 'CIPPGovAppLoaded', $script:GovTenant, $script:ComTenant
    $script:CommercialToken = 'Bearer token-for-sam-app-id'
    $script:GovToken = "Bearer token-for-$($script:GovAppId)"
    $script:CommercialHost = '^https://(graph\.microsoft\.com|outlook\.office365\.com)/'
}

Describe 'Request helpers after a cloud change made in another worker' {
    BeforeEach {
        $null = [CIPP.CIPPTokenCache]::Clear()
        $script:SavedEnv = @{}
        foreach ($Name in $script:EnvNames) { $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name); Remove-Item "env:$Name" -ErrorAction SilentlyContinue }
        $env:ApplicationID = 'sam-app-id'
        $env:ApplicationSecret = 'sam-secret'
        $env:TenantID = $script:Partner
        $env:RefreshToken = 'partner-refresh-token'
        $env:SetFromProfile = 'true'
        Set-Item "env:$($script:GovTenant)" 'gov-tenant-refresh-token'
        Set-Item "env:$($script:ComTenant)" 'com-tenant-refresh-token'

        $script:GovCloud = 'Commercial'
        $script:GovCred = [pscustomobject]@{ ApplicationId = $script:GovAppId; ApplicationSecret = 'gov-secret'; PfxBase64 = $null; HasSecret = $true; HasCertificate = $false; Configured = $true }
        $script:Sent = [System.Collections.Generic.List[object]]::new()

        Mock Get-CippTable { @{} }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like '*directTenant*') {
                return @(
                    [pscustomobject]@{ customerId = $script:GovTenant; defaultDomainName = 'gov.us'; delegatedPrivilegeStatus = 'directTenant'; cloudEnvironment = $script:GovCloud }
                    [pscustomobject]@{ customerId = $script:ComTenant; defaultDomainName = 'com.com'; delegatedPrivilegeStatus = 'directTenant'; cloudEnvironment = 'Commercial' }
                )
            }
            return $null
        }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Update-AzDataTableEntity {}
        Mock Start-Sleep {}
        Mock Get-CIPPGovAppCredential { $env:CIPPGovAppLoaded = 'true'; $script:GovCred }
        Mock Invoke-CIPPRestMethod {
            if ($Uri -like 'https://login.microsoftonline.*') {
                return [pscustomobject]@{ access_token = "token-for-$($Body.client_id)"; refresh_token = 'new-refresh'; expires_in = 3600 }
            }
            $script:Sent.Add([pscustomobject]@{ Uri = [string]$Uri; Authorization = [string]$Headers['Authorization'] })
            if ($Uri -like '*$batch') {
                $Ids = @(($Body | ConvertFrom-Json).requests.id)
                return [pscustomobject]@{ responses = @($Ids | ForEach-Object { [pscustomobject]@{ id = $_; status = 200; body = [pscustomobject]@{ value = @() } } }) }
            }
            [pscustomobject]@{ value = @([pscustomobject]@{ id = '1' }) }
        }

        # This worker: the tenant is Commercial and a commercial token is cached for it.
        $script:WarmUp = {
            param([scriptblock]$Request)
            $script:GovCloud = 'Commercial'
            $null = & $Request
            $script:Sent.Clear()
            # Another worker changes the tenant to USGovHigh (this worker's cache is not cleared there),
            # and this worker's 15-minute cloud marker runs out.
            $script:GovCloud = 'USGovHigh'
            [CIPP.CIPPTokenCache]::Remove([CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker'))
        }
    }

    AfterEach {
        foreach ($Name in $script:SavedEnv.Keys) {
            if ($null -eq $script:SavedEnv[$Name]) { Remove-Item "env:$Name" -ErrorAction SilentlyContinue } else { [Environment]::SetEnvironmentVariable($Name, $script:SavedEnv[$Name]) }
        }
    }

    It '<Helper> sends the government host only the government token' -TestCases @(
        @{ Helper = 'New-GraphGetRequest'; Request = { New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users' -tenantid $script:GovTenant } }
        @{ Helper = 'New-GraphPOSTRequest'; Request = { New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/users/x' -tenantid $script:GovTenant -type PATCH -body '{}' -AddedHeaders @{ 'x-test' = '1' } } }
        @{ Helper = 'New-GraphBulkRequest'; Request = { New-GraphBulkRequest -tenantid $script:GovTenant -Requests @(@{ id = 'u'; method = 'GET'; url = '/users' }) } }
        @{ Helper = 'New-ExoRequest'; Request = { New-ExoRequest -tenantid $script:GovTenant -cmdlet 'Get-Mailbox' } }
        @{ Helper = 'New-ExoBulkRequest'; Request = { New-ExoBulkRequest -tenantid $script:GovTenant -cmdletArray @(@{ CmdletInput = @{ CmdletName = 'Get-Mailbox'; Parameters = @{} } }) } }
    ) {
        param($Helper, $Request)
        & $script:WarmUp $Request

        $null = & $Request

        $script:Sent.Count | Should -BeGreaterThan 0
        foreach ($Call in $script:Sent) {
            $Call.Uri | Should -Not -Match $script:CommercialHost
            $Call.Authorization | Should -BeExactly $script:GovToken
        }
    }

    It 'New-GraphMultiTenantBulkRequest asks for the government token before building the request' {
        # The batch is sent by CIPPRestClient.SendConcurrent (no mock), so stop at the token.
        $script:GovCloud = 'USGovHigh'
        Mock Get-GraphToken { @{ Authorization = $script:CommercialToken } }
        Mock Get-GraphToken { throw 'government token requested' } -ParameterFilter { $RequireCloud -ceq 'USGovHigh' }
        $Result = New-GraphMultiTenantBulkRequest -TenantRequests @(@{ TenantFilter = $script:GovTenant; Requests = @(@{ id = '1'; method = 'GET'; url = '/users' }) })
        $Result[0].Error | Should -BeExactly 'government token requested'
    }

    It 'keeps a government tenant on its cached government token: no extra token request' {
        $script:GovCloud = 'USGovHigh'
        $null = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users' -tenantid $script:GovTenant
        $null = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users' -tenantid $script:GovTenant
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly -ParameterFilter { $Uri -like 'https://login.microsoftonline.*' }
        @($script:Sent.Authorization | Select-Object -Unique) | Should -Be @($script:GovToken)
    }

    It 'leaves a commercial tenant''s request exactly as before: one token call, no -RequireCloud' {
        Mock Get-GraphToken { @{ Authorization = 'Bearer commercial' } }
        $null = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/users' -tenantid $script:ComTenant
        $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/v1.0/users/x' -tenantid $script:ComTenant -body '{}'
        $null = New-GraphBulkRequest -tenantid $script:ComTenant -Requests @(@{ id = 'u'; method = 'GET'; url = '/users' })
        $null = New-ExoRequest -tenantid $script:ComTenant -cmdlet 'Get-Mailbox'
        Should -Invoke Get-GraphToken -Times 4 -Exactly
        Should -Invoke Get-GraphToken -Times 0 -ParameterFilter { -not [string]::IsNullOrEmpty($RequireCloud) }
        $script:Sent.Uri | Should -Not -Match 'microsoft\.us|apps\.mil'
    }

    It 'refuses, with nothing sent, when the table no longer gives the cloud the hosts were chosen for' {
        # Marker says USGovHigh (hosts chosen for it), but the table now says USGovDoD.
        $script:GovCloud = 'USGovHigh'
        $null = Get-GraphToken -tenantid $script:GovTenant
        $script:GovCloud = 'USGovDoD'
        { Get-GraphToken -tenantid $script:GovTenant -RequireCloud 'USGovHigh' -SkipCache $true } | Should -Throw '*cloud environment changed*'
        $script:Sent.Count | Should -Be 0
    }

    It 'never returns the commercial cache key''s token for -RequireCloud' {
        $script:GovCloud = 'Commercial'
        $null = Get-GraphToken -tenantid $script:GovTenant
        $script:GovCloud = 'USGovHigh'
        # A government marker set while the commercial token is still cached (e.g. another thread minted it
        # concurrently with the cloud change).
        [CIPP.CIPPTokenCache]::Store([CIPP.CIPPTokenCache]::BuildKey($script:GovTenant, 'cipp-cloud-environment', $false, '', 'marker'), 'USGovHigh', [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + 900)
        (Get-GraphToken -tenantid $script:GovTenant -RequireCloud 'USGovHigh').Authorization | Should -BeExactly $script:GovToken
    }

    It 'refuses -RequireCloud with explicit app credentials' {
        { Get-GraphToken -tenantid $script:GovTenant -AppID 'x' -AppSecret 'y' -RequireCloud 'USGovHigh' } | Should -Throw '*own app credentials*'
        Should -Invoke Invoke-CIPPRestMethod -Times 0
    }
}
