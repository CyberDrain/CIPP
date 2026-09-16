BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { }
    function Get-ExtensionAPIKey { [CmdletBinding()] param($Extension) }
    function Write-LogMessage { param($API, $Message, $Sev) }
    . (Join-Path $RepoRoot 'Modules/CippExtensions/Public/OneTimeSecret/New-OneTimeSecretLink.ps1')
}

Describe 'New-OneTimeSecretLink' {
    BeforeEach {
        $script:Config = [pscustomobject]@{
            Enabled = $true
            BaseUrl = 'https://nz.onetimesecret.com/'
            EmailAddress = 'test@example.com'
        }
        Mock Get-CIPPAzDataTableEntity { @{ config = (@{ OneTimeSecret = $script:Config } | ConvertTo-Json) } }
        Mock Get-ExtensionAPIKey { 'test-api-key' }
        Mock Write-LogMessage { }
        Mock Invoke-RestMethod { @{ record = @{ secret = @{ identifier = 'secret123'; key = 'legacy123' }; receipt = @{ identifier = 'private123' } } } }
    }

    It 'posts the v2 JSON contract with Basic authentication and returns only the reveal link' {
        New-OneTimeSecretLink -Payload 'a&b=é+"' | Should -Be 'https://nz.onetimesecret.com/secret/secret123'
        Should -Invoke Get-ExtensionAPIKey -Times 1 -Exactly -ParameterFilter { $Extension -eq 'OneTimeSecret' }
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Data = $Body | ConvertFrom-Json
            $Auth = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Headers.Authorization.Substring(6)))
            $Uri -eq 'https://nz.onetimesecret.com/api/v2/secret/conceal' -and
            $Method -eq 'Post' -and $ContentType -eq 'application/json; charset=utf-8' -and
            $MaximumRedirection -eq 0 -and $TimeoutSec -eq 30 -and
            $Auth -eq 'test@example.com:test-api-key' -and
            $Data.secret.secret -ceq 'a&b=é+"' -and $Data.secret.kind -eq 'conceal' -and
            $Data.secret.share_domain -eq '' -and $Data.secret.ttl -eq 86400 -and
            -not $Data.secret.PSObject.Properties['passphrase']
        }
    }

    It 'supports a self-hosted path, expiration, passphrase, and earlier v2 key responses' {
        $script:Config.BaseUrl = 'https://secrets.example.com/ots/'
        $script:Config | Add-Member ExpireAfterHours 2
        $script:Config | Add-Member DefaultPassphrase 'separate passphrase'
        Mock Invoke-RestMethod { @{ record = @{ secret = @{ key = 'oldkey123' } } } }
        New-OneTimeSecretLink -Payload 'password' | Should -Be 'https://secrets.example.com/ots/secret/oldkey123'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Data = $Body | ConvertFrom-Json
            $Uri -eq 'https://secrets.example.com/ots/api/v2/secret/conceal' -and
            $Data.secret.ttl -eq 7200 -and $Data.secret.passphrase -eq 'separate passphrase'
        }
    }

    It 'does not call the service when disabled or missing' {
        $script:Config.Enabled = $false
        New-OneTimeSecretLink -Payload 'password' | Should -BeFalse
        Mock Get-CIPPAzDataTableEntity { $null }
        New-OneTimeSecretLink -Payload 'password' | Should -BeFalse
        Should -Invoke Invoke-RestMethod -Times 0
        Should -Invoke Get-ExtensionAPIKey -Times 0
    }

    It 'does not create a secret under WhatIf' {
        New-OneTimeSecretLink -Payload 'password' -WhatIf | Should -BeFalse
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'rejects invalid URL <Url>' -ForEach @(
        @{ Url = '' }, @{ Url = 'http://example.com' }, @{ Url = 'not-a-url' },
        @{ Url = 'https://user:password@example.com' }, @{ Url = 'https://example.com?key=secret' },
        @{ Url = 'https://example.com/#fragment' }
    ) {
        $script:Config.BaseUrl = $Url
        { New-OneTimeSecretLink -Payload 'password' -ThrowOnError } | Should -Throw '*HTTPS base URL*'
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'rejects invalid expiration <Hours>' -ForEach @(
        @{ Hours = 0 }, @{ Hours = -1 }, @{ Hours = 169 }, @{ Hours = 1.5 }, @{ Hours = 'bad' }
    ) {
        $script:Config | Add-Member ExpireAfterHours $Hours
        { New-OneTimeSecretLink -Payload 'password' -ThrowOnError } | Should -Throw '*whole number*'
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'rejects missing credentials instead of silently creating an anonymous secret' {
        Mock Get-ExtensionAPIKey { '' }
        { New-OneTimeSecretLink -Payload 'password' -ThrowOnError } | Should -Throw '*account email*'
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'rejects an empty payload' {
        { New-OneTimeSecretLink -Payload '' -ThrowOnError } | Should -Throw '*empty password*'
        Should -Invoke Invoke-RestMethod -Times 0
    }

    It 'does not accept a receipt identifier or an invalid secret identifier' {
        Mock Invoke-RestMethod { @{ record = @{ receipt = @{ identifier = 'private123' } } } }
        { New-OneTimeSecretLink -Payload 'password' -ThrowOnError } | Should -Throw '*valid secret identifier*'
        Mock Invoke-RestMethod { @{ record = @{ secret = @{ identifier = '../private' } } } }
        New-OneTimeSecretLink -Payload 'password' | Should -BeFalse
    }

    It 'preserves fallback and sanitizes exceptions and logs' {
        Mock Invoke-RestMethod { throw 'echoed password=test-password APIKey=test-api-key' }
        New-OneTimeSecretLink -Payload 'test-password' | Should -BeFalse
        { New-OneTimeSecretLink -Payload 'test-password' -ThrowOnError } | Should -Throw '*could not create a link*'
        Should -Invoke Write-LogMessage -Times 2 -Exactly -ParameterFilter {
            $API -eq 'OneTimeSecret' -and $Sev -eq 'Error' -and $Message -notmatch 'test-password|test-api-key'
        }
    }
}
