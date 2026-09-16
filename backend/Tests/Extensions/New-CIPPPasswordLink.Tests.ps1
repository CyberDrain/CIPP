BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { }
    function Write-LogMessage { param($API, $Message, $Sev) }
    function New-PwPushLink { param($Payload, [switch]$ThrowOnError) }
    function New-OneTimeSecretLink { param($Payload, $Configuration, [switch]$ThrowOnError) }
    . (Join-Path $RepoRoot 'Modules/CippExtensions/Public/Extension Functions/New-CIPPPasswordLink.ps1')
}

Describe 'New-CIPPPasswordLink provider selection' {
    BeforeEach {
        $script:Config = @{ PWPush = @{ Enabled = $false }; OneTimeSecret = @{ Enabled = $false } }
        Mock Get-CIPPAzDataTableEntity { @{ config = ($script:Config | ConvertTo-Json -Depth 5) } }
        Mock Write-LogMessage { }
        Mock New-PwPushLink { 'https://pwpush.example/p/test' }
        Mock New-OneTimeSecretLink { 'https://secrets.example/secret/test' }
    }

    It 'preserves PWPush for existing configurations' {
        $script:Config.Remove('OneTimeSecret')
        $script:Config.PWPush.Enabled = $true
        New-CIPPPasswordLink -Payload 'password' | Should -Be 'https://pwpush.example/p/test'
        Should -Invoke New-PwPushLink -Times 1 -Exactly -ParameterFilter { $Payload -eq 'password' }
        Should -Invoke New-OneTimeSecretLink -Times 0
    }

    It 'selects PWPush when enabled alone or alongside One-Time Secret' -ForEach @(
        @{ EnableOneTimeSecret = $false }, @{ EnableOneTimeSecret = $true }
    ) {
        $script:Config.PWPush.Enabled = $true
        $script:Config.OneTimeSecret.Enabled = $EnableOneTimeSecret
        New-CIPPPasswordLink -Payload 'password' -ThrowOnError | Should -Be 'https://pwpush.example/p/test'
        Should -Invoke New-PwPushLink -Times 1 -Exactly -ParameterFilter {
            $Payload -eq 'password' -and $ThrowOnError
        }
        Should -Invoke New-OneTimeSecretLink -Times 0
    }

    It 'selects One-Time Secret when PWPush is disabled' {
        $script:Config.OneTimeSecret.Enabled = $true
        New-CIPPPasswordLink -Payload 'password' -ThrowOnError | Should -Be 'https://secrets.example/secret/test'
        Should -Invoke New-OneTimeSecretLink -Times 1 -Exactly -ParameterFilter {
            $Payload -eq 'password' -and $Configuration.Enabled -eq $true -and $ThrowOnError
        }
        Should -Invoke New-PwPushLink -Times 0
    }

    It 'never retries a failed PWPush request through One-Time Secret' {
        $script:Config.PWPush.Enabled = $true
        $script:Config.OneTimeSecret.Enabled = $true
        Mock New-PwPushLink { $false }
        New-CIPPPasswordLink -Payload 'password' | Should -BeFalse
        Should -Invoke New-PwPushLink -Times 1 -Exactly
        Should -Invoke New-OneTimeSecretLink -Times 0
    }

    It 'returns false without calling a provider when neither is enabled' {
        New-CIPPPasswordLink -Payload 'password' | Should -BeFalse
        Should -Invoke New-OneTimeSecretLink -Times 0
        Should -Invoke New-PwPushLink -Times 0
    }

    It 'handles missing and malformed saved configuration' {
        Mock Get-CIPPAzDataTableEntity { $null }
        New-CIPPPasswordLink -Payload 'password' | Should -BeFalse
        Mock Get-CIPPAzDataTableEntity { @{ config = '{invalid' } }
        New-CIPPPasswordLink -Payload 'password' | Should -BeFalse
        { New-CIPPPasswordLink -Payload 'password' -ThrowOnError } | Should -Throw '*configuration*'
        Should -Invoke New-OneTimeSecretLink -Times 0
        Should -Invoke New-PwPushLink -Times 0
    }

    It 'does not invoke either provider under WhatIf' {
        $script:Config.OneTimeSecret.Enabled = $true
        New-CIPPPasswordLink -Payload 'password' -WhatIf | Should -BeFalse
        Should -Invoke New-OneTimeSecretLink -Times 0
        Should -Invoke New-PwPushLink -Times 0
    }
}
