# Invoke-ExecListAppId (redanthrax/CIPP#2): the response gains govApplicationId - the Azure Government
# app's client id, which the direct-tenant consent flow signs in with - and nothing else changes. The
# gov app's secret and certificate never appear in the response, and a gov credential read failure
# never breaks the endpoint the setup wizard and every OAuth button load.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecListAppId.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CIPPAuthentication { }
    function Get-CippKeyVaultName { 'vault' }
    function Get-CippKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function New-GraphBulkRequest { param($Requests, $tenantid, $NoAuthCheck) }
    function New-GraphPOSTRequest { param($type, $Uri, $Body, $tenantid, $NoAuthCheck) }
    function Write-LogMessage { param($message, $Sev, $LogData) }
    function Get-CippException { param($Exception) }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Get-CIPPGovAppCredential.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Get-CIPPGovAppId.ps1')

    $script:EnvNames = 'ApplicationID', 'TenantID', 'GovApplicationID', 'GovApplicationSecret', 'GovSAMCertificate', 'CIPPGovAppLoaded', 'AzureWebJobsStorage', 'NonLocalHostAzurite'
    $script:SamId = 'f8b2c3d4-9e01-4a23-8b45-6c7d8e9f0a1b'
    $script:Partner = 'c7e9a1b2-3d45-4f67-89ab-cdef01234567'
    $script:GovId = '0a0a0a0a-1111-2222-3333-444444444444'
    $script:Request = [pscustomobject]@{ headers = @{ origin = 'https://cipp.example' }; Params = @{ CIPPEndpoint = 'ExecListAppId' } }
}

Describe 'Invoke-ExecListAppId govApplicationId' {
    BeforeEach {
        $script:Saved = @{}
        foreach ($Name in $script:EnvNames) { $script:Saved[$Name] = [Environment]::GetEnvironmentVariable($Name); Remove-Item "env:$Name" -ErrorAction SilentlyContinue }
        $env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=https'
        $script:Vault = @{ ApplicationID = $script:SamId; TenantID = $script:Partner }
        Mock Get-CippKeyVaultSecret {
            if ($script:Vault.ContainsKey($Name)) { return $script:Vault[$Name] }
            throw "Failed to retrieve secret '$Name': 404 SecretNotFound"
        }
        Mock New-GraphBulkRequest { @() }
        Mock Write-LogMessage {}
    }
    AfterEach {
        foreach ($Name in $script:EnvNames) { if ($null -eq $script:Saved[$Name]) { Remove-Item "env:$Name" -ErrorAction SilentlyContinue } else { Set-Item "env:$Name" $script:Saved[$Name] } }
    }

    It 'returns the commercial fields as before and a null govApplicationId when no gov app is set up' {
        $Response = Invoke-ExecListAppId -Request $script:Request
        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $Response.Body.applicationId | Should -Be $script:SamId
        $Response.Body.tenantId | Should -Be $script:Partner
        $Response.Body.govApplicationId | Should -BeNullOrEmpty
        $Response.Body.refreshUrl | Should -BeLike "https://login.microsoftonline.com/$($script:Partner)/oauth2/v2.0/authorize?client_id=$($script:SamId)&*"
        @($Response.Body.Keys | Sort-Object) | Should -Be @('applicationId', 'authenticatedUserDisplayName', 'authenticatedUserPrincipalName', 'govApplicationId', 'isPartnerTenant', 'orgName', 'partnerTenantType', 'refreshUrl', 'tenantId')
    }

    It 'returns the gov app id but never its secret or certificate' {
        $script:Vault['GovApplicationID'] = $script:GovId
        $script:Vault['GovApplicationSecret'] = 'gov-secret-value'
        $script:Vault['GovSAMCertificate'] = 'Z292LXBmeC1wcml2YXRl'

        $Response = Invoke-ExecListAppId -Request $script:Request

        $Response.Body.govApplicationId | Should -Be $script:GovId
        $Json = $Response.Body | ConvertTo-Json -Depth 10
        $Json | Should -Not -BeLike '*gov-secret-value*'
        $Json | Should -Not -BeLike '*Z292LXBmeC1wcml2YXRl*'
    }

    It 'returns a null govApplicationId for a stored id that is not a GUID' {
        $script:Vault['GovApplicationID'] = 'not-a-guid'
        $script:Vault['GovApplicationSecret'] = 'gov-secret-value'
        (Invoke-ExecListAppId -Request $script:Request).Body.govApplicationId | Should -BeNullOrEmpty
    }

    It 'still answers when the gov credentials cannot be read' {
        Mock Get-CippKeyVaultSecret {
            if ($Name -like 'Gov*') { throw 'Forbidden 403' }
            $script:Vault[$Name]
        }
        $Response = Invoke-ExecListAppId -Request $script:Request
        $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
        $Response.Body.applicationId | Should -Be $script:SamId
        $Response.Body.govApplicationId | Should -BeNullOrEmpty
    }

    It 'reads only the gov app id from Key Vault, never the gov secret or certificate' {
        $script:Vault['GovApplicationID'] = $script:GovId
        $script:Vault['GovApplicationSecret'] = 'gov-secret-value'
        $script:Vault['GovSAMCertificate'] = 'Z292LXBmeC1wcml2YXRl'

        $null = Invoke-ExecListAppId -Request $script:Request

        Should -Invoke Get-CippKeyVaultSecret -Times 1 -Exactly -ParameterFilter { $Name -eq 'GovApplicationID' }
        Should -Invoke Get-CippKeyVaultSecret -Times 0 -ParameterFilter { $Name -in 'GovApplicationSecret', 'GovSAMCertificate' }
        $env:GovApplicationSecret | Should -BeNullOrEmpty
        $env:GovSAMCertificate | Should -BeNullOrEmpty
    }

    It 'uses the gov app id already loaded in the process without reading Key Vault' {
        $env:CIPPGovAppLoaded = 'true'
        $env:GovApplicationID = $script:GovId
        Mock Get-CIPPAuthentication { }

        (Invoke-ExecListAppId -Request $script:Request).Body.govApplicationId | Should -Be $script:GovId
        Should -Invoke Get-CippKeyVaultSecret -Times 0 -ParameterFilter { $Name -like 'Gov*' }
    }

    It 'reads the gov app id from dev storage' {
        $env:AzureWebJobsStorage = 'UseDevelopmentStorage=true'
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ ApplicationID = $script:SamId; TenantID = $script:Partner; GovApplicationID = $script:GovId; GovApplicationSecret = 'gov-secret-value' } }

        $Response = Invoke-ExecListAppId -Request $script:Request

        $Response.Body.govApplicationId | Should -Be $script:GovId
        $env:GovApplicationSecret | Should -BeNullOrEmpty
    }
}
