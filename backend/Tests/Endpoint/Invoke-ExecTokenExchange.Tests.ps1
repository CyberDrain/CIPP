# Pester tests for Invoke-ExecTokenExchange certificate assertions.
# The Direct Add / SAM OAuth popup posts to the /organizations token endpoint. When certificate
# auth is on, the client assertion aud claim must equal that tokenUrl - using $env:TenantID
# (partner GUID) produces AADSTS700023.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecTokenExchange.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ExecTokenExchange.ps1 under Modules/' }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
        [object]$Headers
    }

    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CippKeyVaultName { 'test-kv' }
    function Write-LogMessage { param($API, $message, $Sev) }
    function Get-CIPPAuthentication { $true }
    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Get-CippKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
    function Get-CIPPSAMCertificate { param($Name, [switch]$SkipCache) }
    function New-CIPPCertificateAssertion { param($TenantId, $AppId, $Certificate, $Audience) }
    function Invoke-RestMethod {
        param($Uri, $Method, $Body, $ContentType, [switch]$SkipHttpErrorCheck)
    }

    . $FunctionPath

    function New-TokenExchangeRequest {
        param(
            [string]$TokenUrl = 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token',
            [string]$AppId = 'sam-app-id'
        )
        [pscustomobject]@{
            Params = @{ CIPPEndpoint = 'ExecTokenExchange' }
            Body   = [pscustomobject]@{
                tokenUrl     = $TokenUrl
                tenantId     = $AppId
                tokenRequest = [pscustomobject]@{
                    grant_type   = 'authorization_code'
                    client_id    = $AppId
                    code         = 'auth-code'
                    redirect_uri = 'https://cipp.example.com/authredirect'
                }
            }
        }
    }
}

Describe 'Invoke-ExecTokenExchange certificate assertion audience' {
    BeforeEach {
        $script:SavedEnv = @{}
        foreach ($Name in 'CertificateAuthMode', 'ApplicationSecret', 'TenantID', 'AzureWebJobsStorage', 'NonLocalHostAzurite') {
            $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name)
        }
        # Partner tenant GUID - the regression was using this as aud instead of tokenUrl.
        $env:TenantID = '11111111-2222-3333-4444-555555555555'
        $env:CertificateAuthMode = $true
        $env:ApplicationSecret = 'AppSecret'
        Remove-Item env:AzureWebJobsStorage -ErrorAction SilentlyContinue
        Remove-Item env:NonLocalHostAzurite -ErrorAction SilentlyContinue

        Mock Write-LogMessage {}
        Mock Get-CippKeyVaultName { 'test-kv' }
        Mock Get-CIPPAuthentication { $true }
        Mock Get-CIPPSAMCertificate { [pscustomobject]@{ Certificate = 'CERT-OBJECT'; Thumbprint = 'ABC' } }
        Mock New-CIPPCertificateAssertion { 'signed.jwt.assertion' }
        Mock Invoke-RestMethod { @{ access_token = 'token'; refresh_token = 'refresh'; expires_in = 3600 } }
        Mock Start-Sleep {}
    }

    AfterEach {
        foreach ($Name in $script:SavedEnv.Keys) {
            if ($null -eq $script:SavedEnv[$Name]) {
                Remove-Item "env:$Name" -ErrorAction SilentlyContinue
            } else {
                Set-Item "env:$Name" -Value $script:SavedEnv[$Name]
            }
        }
    }

    It 'builds the certificate assertion aud from the organizations tokenUrl, not env:TenantID' {
        $TokenUrl = 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token'
        $Response = Invoke-ExecTokenExchange -Request (New-TokenExchangeRequest -TokenUrl $TokenUrl) -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke New-CIPPCertificateAssertion -Times 1 -Exactly -ParameterFilter {
            $Audience -eq $TokenUrl -and
            $TenantId -eq 'organizations' -and
            $AppId -eq 'sam-app-id'
        }
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -eq $TokenUrl -and
            $Body.ContainsKey('client_assertion') -and
            $Body['client_assertion_type'] -eq 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer' -and
            -not $Body.ContainsKey('client_secret')
        }
    }
}

# redanthrax/CIPP#2: a direct government tenant consents against its cloud's authority with the Azure
# Government app. The commercial exchange is unchanged when no cloud (or Commercial) is sent.
Describe 'Invoke-ExecTokenExchange government cloud' {
    BeforeAll {
        function Get-CIPPGovAppCredential { param([switch]$Force) }
        . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPCloudEndpoint.ps1')
        . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/ConvertTo-CIPPCloudScope.ps1')
        . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/ConvertTo-CIPPCloudUri.ps1')
        . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Resolve-CIPPCloudHost.ps1')
        . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPPartnerCloudEnvironment.ps1')
        . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPCloudTokenRoute.ps1')
        $script:GovAppId = '9a9a9a9a-0000-0000-0000-000000000000'

        function New-GovRequest {
            param($Cloud = 'USGovHigh', $TokenUrl = 'https://login.microsoftonline.us/organizations/oauth2/v2.0/token')
            $Req = New-TokenExchangeRequest -TokenUrl $TokenUrl -AppId 'whatever-the-browser-sent'
            $Req.Body | Add-Member -NotePropertyName cloudEnvironment -NotePropertyValue $Cloud
            $Req
        }
    }

    BeforeEach {
        $script:SavedEnv = @{}
        foreach ($Name in 'CertificateAuthMode', 'ApplicationID', 'ApplicationSecret', 'TenantID', 'AzureWebJobsStorage', 'NonLocalHostAzurite', 'CIPP_PARTNER_CLOUD') {
            $script:SavedEnv[$Name] = [Environment]::GetEnvironmentVariable($Name)
            Remove-Item "env:$Name" -ErrorAction SilentlyContinue
        }
        $env:ApplicationID = 'sam-app-id'
        $env:ApplicationSecret = 'sam-secret'
        $script:GovCred = [pscustomobject]@{ ApplicationId = $script:GovAppId; ApplicationSecret = 'gov-secret'; PfxBase64 = $null; HasSecret = $true; HasCertificate = $false; Configured = $true }

        Mock Write-LogMessage {}
        Mock Get-CIPPAuthentication { $true }
        Mock Get-CIPPGovAppCredential { $script:GovCred }
        Mock Get-CIPPSAMCertificate { [pscustomobject]@{ Certificate = 'GOV-CERT'; Thumbprint = 'GOV' } }
        Mock New-CIPPCertificateAssertion { 'signed.jwt.assertion' }
        Mock Invoke-RestMethod { @{ access_token = 'token'; refresh_token = 'refresh'; expires_in = 3600 } }
        Mock Start-Sleep {}
    }

    AfterEach {
        foreach ($Name in $script:SavedEnv.Keys) {
            if ($null -eq $script:SavedEnv[$Name]) { Remove-Item "env:$Name" -ErrorAction SilentlyContinue } else { Set-Item "env:$Name" -Value $script:SavedEnv[$Name] }
        }
    }

    It 'exchanges a <Cloud> code at the government authority with the Azure Government app and secret' -TestCases @(@{ Cloud = 'USGovHigh' }, @{ Cloud = 'USGovDoD' }) {
        param($Cloud)
        $Response = Invoke-ExecTokenExchange -Request (New-GovRequest -Cloud $Cloud) -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://login.microsoftonline.us/organizations/oauth2/v2.0/token' -and
            $Body['client_id'] -eq $script:GovAppId -and $Body['client_secret'] -eq 'gov-secret'
        }
        Should -Invoke Invoke-RestMethod -Times 0 -ParameterFilter { $Body['client_secret'] -eq 'sam-secret' -or $Body['client_id'] -eq 'sam-app-id' }
    }

    It 'signs with the government certificate for the government audience when there is no secret' {
        $script:GovCred = [pscustomobject]@{ ApplicationId = $script:GovAppId; ApplicationSecret = $null; PfxBase64 = 'pfx'; HasSecret = $false; HasCertificate = $true; Configured = $true }
        $Response = Invoke-ExecTokenExchange -Request (New-GovRequest) -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Get-CIPPSAMCertificate -ParameterFilter { $Name -eq 'GovSAMCertificate' }
        Should -Invoke New-CIPPCertificateAssertion -ParameterFilter { $AppId -eq $script:GovAppId -and $Audience -eq 'https://login.microsoftonline.us/organizations/oauth2/v2.0/token' }
        Should -Invoke Invoke-RestMethod -ParameterFilter { -not $Body.ContainsKey('client_secret') -and $Body['client_assertion'] }
    }

    It 'fails without any token request when the Azure Government app is not configured' {
        $script:GovCred = [pscustomobject]@{ ApplicationId = $null; ApplicationSecret = $null; PfxBase64 = $null; HasSecret = $false; HasCertificate = $false; Configured = $false }
        $Response = Invoke-ExecTokenExchange -Request (New-GovRequest) -TriggerMetadata $null
        $Response.StatusCode | Should -Not -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.error_description | Should -BeLike '*Azure Government app not configured*'
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'rejects the commercial token endpoint for a government exchange' {
        $Response = Invoke-ExecTokenExchange -Request (New-GovRequest -TokenUrl 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token') -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'rejects the government token endpoint for a commercial exchange' {
        $Response = Invoke-ExecTokenExchange -Request (New-TokenExchangeRequest -TokenUrl 'https://login.microsoftonline.us/organizations/oauth2/v2.0/token') -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'rejects a cloudEnvironment of <Value>' -TestCases @(@{ Value = 'usgovhigh' }, @{ Value = '' }, @{ Value = 'login.microsoftonline.us' }) {
        param($Value)
        $Response = Invoke-ExecTokenExchange -Request (New-GovRequest -Cloud $Value) -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'keeps the commercial exchange on the SAM app when Commercial is sent' {
        $Response = Invoke-ExecTokenExchange -Request (New-GovRequest -Cloud 'Commercial' -TokenUrl 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token') -TriggerMetadata $null
        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        Should -Invoke Invoke-RestMethod -Times 1 -ParameterFilter { $Uri -eq 'https://login.microsoftonline.com/organizations/oauth2/v2.0/token' -and $Body['client_id'] -eq 'sam-app-id' -and $Body['client_secret'] -eq 'sam-secret' }
        Should -Invoke Get-CIPPGovAppCredential -Times 0
    }
}
