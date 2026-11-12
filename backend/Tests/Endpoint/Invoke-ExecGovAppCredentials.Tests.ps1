# Azure Government app credentials (redanthrax/CIPP#2): stored next to the SAM app's, never returned by
# the endpoint, loaded lazily, and "not configured" is reported rather than guessed.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $EndpointPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ExecGovAppCredentials.ps1' -File | Select-Object -First 1 -ExpandProperty FullName

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [psobject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not $Accelerators::Get.ContainsKey('HttpStatusCode')) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CIPPTable { param($tablename) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-CippKeyVaultName { 'vault' }
    function Get-CippKeyVaultSecret { param($VaultName, $Name, [switch]$AsPlainText) }
    function Set-CippKeyVaultSecret { param($VaultName, $Name, $SecretValue) }
    function Set-CIPPCredentialVersion { }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = $Exception.Exception.Message } }
    function Get-CIPPSAMCertificate { param($Name, [switch]$SkipCache) }
    function New-CIPPSAMCertificate { param($SubjectName) }
    function Set-CIPPSAMCertificate { param($PfxBase64, $Name) }
    function Test-CIPPAccess { param($Request, [switch]$TenantList) $script:TenantAccess }
    function Get-CIPPFeatureFlag { param($Id) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Get-CIPPGovAppCredential.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Set-CIPPGovAppCredential.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPCloudEndpoint.ps1')
    . $EndpointPath

    $script:EnvNames = 'GovApplicationID', 'GovApplicationSecret', 'GovSAMCertificate', 'CIPPGovAppLoaded', 'AzureWebJobsStorage', 'NonLocalHostAzurite'
    $script:GovId = '0a0a0a0a-1111-2222-3333-444444444444'

    function New-Request {
        param($Body = @{}, $Query = @{})
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecGovAppCredentials' }; Headers = @{ origin = 'https://cipp.example' }; Body = [pscustomobject]$Body; Query = [pscustomobject]$Query }
    }

    # A real self-signed certificate so the public-part export is exercised.
    $Rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $Req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=test', $Rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $script:TestCert = $Req.CreateSelfSigned([datetimeoffset]::UtcNow.AddDays(-1), [datetimeoffset]::UtcNow.AddDays(30))
}

Describe 'Azure Government app credentials' {
    BeforeEach {
        $script:Saved = @{}
        foreach ($Name in $script:EnvNames) { $script:Saved[$Name] = [Environment]::GetEnvironmentVariable($Name); Remove-Item "env:$Name" -ErrorAction SilentlyContinue }
        $script:Vault = @{}
        Mock Get-CippKeyVaultSecret {
            if ($script:Vault.ContainsKey($Name)) { return $script:Vault[$Name] }
            throw "Failed to retrieve secret '$Name' from vault: 404 SecretNotFound"
        }
        Mock Set-CippKeyVaultSecret { $script:Vault[$Name] = [System.Net.NetworkCredential]::new('', $SecretValue).Password }
        Mock Set-CIPPCredentialVersion {}
        Mock Write-LogMessage {}
        $script:TenantAccess = @('AllTenants')
    }
    AfterEach {
        foreach ($Name in $script:EnvNames) { if ($null -eq $script:Saved[$Name]) { Remove-Item "env:$Name" -ErrorAction SilentlyContinue } else { Set-Item "env:$Name" $script:Saved[$Name] } }
    }

    Context 'Get-CIPPGovAppCredential' {
        It 'reports not configured when nothing is stored' {
            $Result = Get-CIPPGovAppCredential
            $Result.Configured | Should -BeFalse
            $Result.ApplicationId | Should -BeNullOrEmpty
        }

        It 'reports not configured with an id but no secret or certificate' {
            $script:Vault['GovApplicationID'] = $script:GovId
            (Get-CIPPGovAppCredential).Configured | Should -BeFalse
        }

        It 'reports not configured for an id that is not a GUID' {
            $script:Vault['GovApplicationID'] = 'not-a-guid'
            $script:Vault['GovApplicationSecret'] = 's'
            (Get-CIPPGovAppCredential).Configured | Should -BeFalse
        }

        It 'loads an id and secret once and serves later calls from the process cache' {
            $script:Vault['GovApplicationID'] = $script:GovId
            $script:Vault['GovApplicationSecret'] = 'gov-secret'
            $First = Get-CIPPGovAppCredential
            $Second = Get-CIPPGovAppCredential
            $First.Configured | Should -BeTrue
            $Second.ApplicationSecret | Should -Be 'gov-secret'
            Should -Invoke Get-CippKeyVaultSecret -Times 3 -Exactly
        }

        It 'never reads the commercial SAM secrets' {
            $null = Get-CIPPGovAppCredential
            Should -Invoke Get-CippKeyVaultSecret -Times 0 -ParameterFilter { $Name -in 'ApplicationID', 'ApplicationSecret', 'SAMCertificate', 'RefreshToken' }
        }

        It 'rethrows a Key Vault failure other than not found instead of caching "not configured"' {
            Mock Get-CippKeyVaultSecret { throw 'Forbidden 403' }
            { Get-CIPPGovAppCredential } | Should -Throw '*403*'
            $env:CIPPGovAppLoaded | Should -BeNullOrEmpty
        }

        It 'reads the DevSecrets table when running locally' {
            $env:AzureWebJobsStorage = 'UseDevelopmentStorage=true'
            Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ GovApplicationID = $script:GovId; GovSAMCertificate = 'cGZ4' } }
            $Result = Get-CIPPGovAppCredential
            $Result.Configured | Should -BeTrue
            $Result.HasCertificate | Should -BeTrue
            Should -Invoke Get-CippKeyVaultSecret -Times 0
        }
    }

    Context 'Set-CIPPGovAppCredential' {
        It 'stores the id and secret under the Gov names and bumps the credential version' {
            Set-CIPPGovAppCredential -ApplicationId $script:GovId -ApplicationSecret 'new-secret'
            $script:Vault['GovApplicationID'] | Should -Be $script:GovId
            $script:Vault['GovApplicationSecret'] | Should -Be 'new-secret'
            $script:Vault.ContainsKey('ApplicationSecret') | Should -BeFalse
            Should -Invoke Set-CIPPCredentialVersion -Times 1
        }

        It 'keeps the stored secret when only the id is given' {
            $script:Vault['GovApplicationSecret'] = 'old'
            Set-CIPPGovAppCredential -ApplicationId $script:GovId
            $script:Vault['GovApplicationSecret'] | Should -Be 'old'
        }

        It 'rejects an id that is not a GUID' {
            { Set-CIPPGovAppCredential -ApplicationId "$($script:GovId)`n" } | Should -Throw '*GUID*'
            Should -Invoke Set-CippKeyVaultSecret -Times 0
        }

        It 'drops the cached copy so the next read sees the new values' {
            $script:Vault['GovApplicationID'] = $script:GovId
            $script:Vault['GovApplicationSecret'] = 'old'
            $null = Get-CIPPGovAppCredential
            Set-CIPPGovAppCredential -ApplicationId $script:GovId -ApplicationSecret 'rotated'
            (Get-CIPPGovAppCredential).ApplicationSecret | Should -Be 'rotated'
        }
    }

    Context 'Invoke-ExecGovAppCredentials' {
        It 'returns status without any secret or private key' {
            $script:Vault['GovApplicationID'] = $script:GovId
            $script:Vault['GovApplicationSecret'] = 'gov-secret-value'
            $script:Vault['GovSAMCertificate'] = 'cGZ4LXByaXZhdGU='
            Mock Get-CIPPSAMCertificate { [pscustomobject]@{ Certificate = $script:TestCert; Thumbprint = $script:TestCert.Thumbprint; NotAfter = $script:TestCert.NotAfter; PfxBase64 = 'cGZ4LXByaXZhdGU=' } }

            $Response = Invoke-ExecGovAppCredentials -Request (New-Request)

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            $Results = $Response.Body.Results
            $Results.configured | Should -BeTrue
            $Results.applicationId | Should -Be $script:GovId
            $Results.hasSecret | Should -BeTrue
            $Results.authority | Should -BeExactly 'https://login.microsoftonline.us/organizations'
            $Results.redirectUri | Should -Be 'https://cipp.example/authredirect'
            $Results.certificate.thumbprint | Should -Be $script:TestCert.Thumbprint
            $Json = $Response.Body | ConvertTo-Json -Depth 10
            $Json | Should -Not -BeLike '*gov-secret-value*'
            $Json | Should -Not -BeLike '*cGZ4LXByaXZhdGU=*'
            # The public certificate parses and carries no private key
            $Public = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([Convert]::FromBase64String($Results.certificate.publicCertificate))
            $Public.HasPrivateKey | Should -BeFalse
        }

        It 'reports the <Expected> as the credential in use (certificate auth <CertMode>, secret stored <HasSecret>)' -TestCases @(
            @{ CertMode = $true; HasSecret = $true; Expected = 'certificate' }
            @{ CertMode = $true; HasSecret = $false; Expected = 'certificate' }
            @{ CertMode = $false; HasSecret = $false; Expected = 'certificate' }
            @{ CertMode = $false; HasSecret = $true; Expected = 'secret' }
        ) {
            param($CertMode, $HasSecret, $Expected)
            $script:CertMode = $CertMode
            Mock Get-CIPPFeatureFlag { [pscustomobject]@{ Id = $Id; Enabled = $script:CertMode } }
            $script:Vault['GovApplicationID'] = $script:GovId
            if ($HasSecret) { $script:Vault['GovApplicationSecret'] = 'gov-secret-value' }

            $Results = (Invoke-ExecGovAppCredentials -Request (New-Request)).Body.Results

            $Results.certificateAuthMode | Should -Be $CertMode
            $Results.credentialInUse | Should -BeExactly $Expected
            Should -Invoke Get-CIPPFeatureFlag -ParameterFilter { $Id -eq 'CertificateAuthentication' }
        }

        It 'falls back to the process certificate auth mode when the feature flag cannot be read' {
            Mock Get-CIPPFeatureFlag { throw 'table unavailable' }
            $SavedMode = $env:CertificateAuthMode
            try {
                $env:CertificateAuthMode = 'True'
                $script:Vault['GovApplicationID'] = $script:GovId
                $script:Vault['GovApplicationSecret'] = 'gov-secret-value'
                $Results = (Invoke-ExecGovAppCredentials -Request (New-Request)).Body.Results
                $Results.certificateAuthMode | Should -BeTrue
                $Results.credentialInUse | Should -BeExactly 'certificate'
            } finally {
                $env:CertificateAuthMode = $SavedMode
            }
        }

        It 'saves the id and secret' {
            $Response = Invoke-ExecGovAppCredentials -Request (New-Request -Body @{ Action = 'Save'; applicationId = $script:GovId; applicationSecret = 'abc' })
            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            $script:Vault['GovApplicationSecret'] | Should -Be 'abc'
            Should -Invoke Write-LogMessage -ParameterFilter { $message -notlike '*abc*' }
            Should -Invoke Write-LogMessage -Times 0 -ParameterFilter { $message -like '*abc*' }
        }

        It 'refuses to save an invalid id' {
            $Response = Invoke-ExecGovAppCredentials -Request (New-Request -Body @{ Action = 'Save'; applicationId = 'nope'; applicationSecret = 'abc' })
            $Response.StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
            Should -Invoke Set-CippKeyVaultSecret -Times 0
        }

        It 'generates a certificate under GovSAMCertificate and returns only the public part' {
            Mock New-CIPPSAMCertificate { [pscustomobject]@{ PfxBase64 = 'private-pfx' } }
            Mock Set-CIPPSAMCertificate {}
            Mock Get-CIPPSAMCertificate { [pscustomobject]@{ Certificate = $script:TestCert; Thumbprint = $script:TestCert.Thumbprint; NotAfter = $script:TestCert.NotAfter; PfxBase64 = 'private-pfx' } }

            $Response = Invoke-ExecGovAppCredentials -Request (New-Request -Body @{ Action = 'GenerateCertificate' })

            $Response.StatusCode | Should -Be ([HttpStatusCode]::OK)
            Should -Invoke Set-CIPPSAMCertificate -Times 1 -ParameterFilter { $Name -eq 'GovSAMCertificate' -and $PfxBase64 -eq 'private-pfx' }
            Should -Invoke Set-CIPPSAMCertificate -Times 0 -ParameterFilter { $Name -ne 'GovSAMCertificate' }
            ($Response.Body | ConvertTo-Json -Depth 10) | Should -Not -BeLike '*private-pfx*'
            $Response.Body.Results.publicCertificate | Should -Not -BeNullOrEmpty
        }

        It 'refuses <Action> for a tenant-restricted caller without writing anything' -TestCases @(
            @{ Action = 'Save' }
            @{ Action = 'GenerateCertificate' }
        ) {
            param($Action)
            $script:TenantAccess = @('22222222-2222-2222-2222-222222222222')
            Mock New-CIPPSAMCertificate {}
            Mock Set-CIPPSAMCertificate {}
            $Response = Invoke-ExecGovAppCredentials -Request (New-Request -Body @{ Action = $Action; applicationId = $script:GovId; applicationSecret = 'abc' })
            $Response.StatusCode | Should -Be ([HttpStatusCode]::Forbidden)
            Should -Invoke Set-CippKeyVaultSecret -Times 0
            Should -Invoke New-CIPPSAMCertificate -Times 0
            Should -Invoke Set-CIPPSAMCertificate -Times 0
        }

        It 'rejects an unknown action' {
            (Invoke-ExecGovAppCredentials -Request (New-Request -Body @{ Action = 'Dump' })).StatusCode | Should -Be ([HttpStatusCode]::BadRequest)
        }
    }
}
