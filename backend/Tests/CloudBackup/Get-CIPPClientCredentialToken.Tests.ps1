BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Body, $ContentType, [switch]$SkipHttpErrorCheck) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup/Get-CIPPClientCredentialToken.ps1')
}

Describe 'Get-CIPPClientCredentialToken' {
    BeforeEach {
        $script:CIPPClientCredentialTokenCache = $null
        $script:Calls = 0
        Mock Invoke-CIPPRestMethod { $script:Calls++; [pscustomobject]@{ access_token = "token-$script:Calls"; expires_in = 3599 } }
    }

    It 'posts a client credentials grant to the tenant authority' {
        Get-CIPPClientCredentialToken -TenantId 'contoso.onmicrosoft.com' -ClientId 'app' -ClientSecret 'pw' -Scope 'https://storage.azure.com/.default' | Should -Be 'token-1'
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -ParameterFilter {
            $Uri -eq 'https://login.microsoftonline.com/contoso.onmicrosoft.com/oauth2/v2.0/token' -and $Method -eq 'POST' -and
            $Body.grant_type -eq 'client_credentials' -and $Body.client_id -eq 'app' -and $Body.client_secret -eq 'pw' -and
            $Body.scope -eq 'https://storage.azure.com/.default' -and $ContentType -eq 'application/x-www-form-urlencoded'
        }
    }

    It 'reuses the token for the same app, scope and secret' {
        $null = Get-CIPPClientCredentialToken -TenantId 't' -ClientId 'app' -ClientSecret 'pw' -Scope 's'
        Get-CIPPClientCredentialToken -TenantId 't' -ClientId 'app' -ClientSecret 'pw' -Scope 's' | Should -Be 'token-1'
        Should -Invoke Invoke-CIPPRestMethod -Times 1 -Exactly
    }

    It 'gets a new token for another scope or a changed secret' {
        $null = Get-CIPPClientCredentialToken -TenantId 't' -ClientId 'app' -ClientSecret 'pw' -Scope 's'
        Get-CIPPClientCredentialToken -TenantId 't' -ClientId 'app' -ClientSecret 'pw' -Scope 'other' | Should -Be 'token-2'
        Get-CIPPClientCredentialToken -TenantId 't' -ClientId 'app' -ClientSecret 'new' -Scope 's' | Should -Be 'token-3'
    }

    It 'does not keep the secret in the memo key' {
        $null = Get-CIPPClientCredentialToken -TenantId 't' -ClientId 'app' -ClientSecret 'very-secret-value' -Scope 's'
        ($script:CIPPClientCredentialTokenCache.Keys -join ' ') | Should -Not -Match 'very-secret-value'
    }

    It 'gets a new token once the cached one is near expiry' {
        $null = Get-CIPPClientCredentialToken -TenantId 't' -ClientId 'app' -ClientSecret 'pw' -Scope 's'
        foreach ($Entry in $script:CIPPClientCredentialTokenCache.Values) { $Entry.Expires = [datetime]::UtcNow.AddSeconds(-1) }
        Get-CIPPClientCredentialToken -TenantId 't' -ClientId 'app' -ClientSecret 'pw' -Scope 's' | Should -Be 'token-2'
        $script:CIPPClientCredentialTokenCache.Count | Should -Be 1
    }

    It 'never holds more than 50 tokens' {
        foreach ($i in 1..60) { $null = Get-CIPPClientCredentialToken -TenantId 't' -ClientId "app$i" -ClientSecret 'pw' -Scope 's' }
        $script:CIPPClientCredentialTokenCache.Count | Should -BeLessOrEqual 50
    }

    It 'throws the Entra error without the trace details or the secret' {
        Mock Invoke-CIPPRestMethod { [pscustomobject]@{ error = 'invalid_client'; error_description = "AADSTS7000215: Invalid client secret provided. Trace ID: abc`r`nCorrelation ID: def" } }
        { Get-CIPPClientCredentialToken -TenantId 't' -ClientId 'app' -ClientSecret 'pw-value' -Scope 's' } | Should -Throw -ExpectedMessage '*AADSTS7000215: Invalid client secret provided.'
        $script:CIPPClientCredentialTokenCache.Count | Should -Be 0
    }

    It 'rejects a tenant value that would change the token URL' {
        { Get-CIPPClientCredentialToken -TenantId 'evil.com/x?' -ClientId 'app' -ClientSecret 'pw' -Scope 's' } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke Invoke-CIPPRestMethod -Times 0 -Exactly
    }
}
