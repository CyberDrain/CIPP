BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    ([PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')).GetMethod('Add').Invoke(
        $null, @('HttpStatusCode', [System.Net.HttpStatusCode]))
    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    function Get-CIPPTable { param($TableName) @{} }
    function Get-CIPPAzDataTableEntity { }
    function New-OneTimeSecretLink { param($Payload, $Configuration, [switch]$ThrowOnError) }
    function New-PwPushLink { param($Payload, [switch]$ThrowOnError) }
    . (Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/CIPP/Extensions/Invoke-ExecExtensionTest.ps1')
}

Describe 'One-Time Secret integration test endpoint' {
    BeforeEach {
        $script:Config = @{ OneTimeSecret = @{ Enabled = $true }; PWPush = @{ Enabled = $true } }
        Mock Get-CIPPAzDataTableEntity { @{ config = ($script:Config | ConvertTo-Json) } }
        Mock New-OneTimeSecretLink { 'https://secrets.example/secret/test' }
        Mock New-PwPushLink { 'https://pwpush.example/p/test' }
        $Request = @{ Query = @{ extensionName = 'OneTimeSecret' } }
    }

    It 'returns a copyable link using harmless test content' {
        $Response = Invoke-ExecExtensionTest -Request $Request
        $Response.Body.Results[0].copyField | Should -Be 'https://secrets.example/secret/test'
        $Response.Body.Results[0].state | Should -Be 'success'
        Should -Invoke New-OneTimeSecretLink -Times 1 -Exactly -ParameterFilter {
            $Payload -eq 'This is a test from CIPP' -and $ThrowOnError -and $Configuration.Enabled
        }
        Should -Invoke New-PwPushLink -Times 0
    }

    It 'explains that disabled settings must be saved first' {
        $script:Config.OneTimeSecret.Enabled = $false
        (Invoke-ExecExtensionTest -Request $Request).Body.Results | Should -Match 'not enabled'
        Should -Invoke New-OneTimeSecretLink -Times 0
    }

    It 'reports link creation failures without claiming success' {
        Mock New-OneTimeSecretLink { throw 'One-Time Secret returned HTTP 401.' }
        (Invoke-ExecExtensionTest -Request $Request).Body.Results | Should -Match 'test failed.*401'
        Mock New-OneTimeSecretLink { $false }
        (Invoke-ExecExtensionTest -Request $Request).Body.Results | Should -Match 'did not return a link'
    }

    It 'still tests PWPush directly when both providers are enabled' {
        $Request.Query.extensionName = 'PWPush'
        (Invoke-ExecExtensionTest -Request $Request).Body.Results[0].copyField | Should -Be 'https://pwpush.example/p/test'
        Should -Invoke New-OneTimeSecretLink -Times 0
        Should -Invoke New-PwPushLink -Times 1 -Exactly
    }
}
