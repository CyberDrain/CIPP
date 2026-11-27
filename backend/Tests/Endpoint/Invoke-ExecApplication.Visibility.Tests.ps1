# Pester tests for the tag-backed visibility actions on Invoke-ExecApplication.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [object]$ContentType
    }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$($Exception.Exception.Message)" } }
    function Get-NormalizedError { param($message) $message }
    function New-GraphPOSTRequest { param($Uri, $Type, $Body, $tenantid, $AsApp) }
    function New-GraphGetRequest { param($Uri, $tenantid, $AsApp) }
    function Get-CippProtectedAppId { }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-IsGuid.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')
    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Tenant/Administration/Application Approval/Invoke-ExecApplication.ps1'
    . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath $EndpointPath -Raw)))

    function New-Request {
        param($Action, $Type = 'servicePrincipals')
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecApplication' }
            Headers = @{}
            Query   = [pscustomobject]@{}
            Body    = [pscustomobject]@{ Id = '00000000-0000-0000-0000-0000000000a1'; Type = $Type; tenantFilter = 'contoso.onmicrosoft.com'; Action = $Action }
        }
    }
}

Describe 'Visibility actions' {
    It '<Action> sends tags <Expected> when the app has <Current>' -ForEach @(
        @{ Action = 'ShowInEnterpriseApps'; Current = @(); Expected = '["WindowsAzureActiveDirectoryIntegratedApp"]' }
        @{ Action = 'ShowInEnterpriseApps'; Current = @('HideApp'); Expected = '["HideApp","WindowsAzureActiveDirectoryIntegratedApp"]' }
        @{ Action = 'ShowInEnterpriseApps'; Current = @('WindowsAzureActiveDirectoryIntegratedApp'); Expected = '["WindowsAzureActiveDirectoryIntegratedApp"]' }
        @{ Action = 'HideFromEnterpriseApps'; Current = @('WindowsAzureActiveDirectoryIntegratedApp'); Expected = '[]' }
        @{ Action = 'HideFromEnterpriseApps'; Current = @('HideApp', 'WindowsAzureActiveDirectoryIntegratedApp'); Expected = '["HideApp"]' }
        @{ Action = 'Hide'; Current = @('WindowsAzureActiveDirectoryIntegratedApp'); Expected = '["WindowsAzureActiveDirectoryIntegratedApp","HideApp"]' }
        @{ Action = 'Show'; Current = @('HideApp', 'WindowsAzureActiveDirectoryIntegratedApp'); Expected = '["WindowsAzureActiveDirectoryIntegratedApp"]' }
        @{ Action = 'Show'; Current = @('HideApp'); Expected = '[]' }
    ) {
        $script:CurrentTags = $Current
        Mock New-GraphGetRequest -MockWith { [pscustomobject]@{ appId = '00000000-0000-0000-0000-0000000000ff'; displayName = 'Contoso App'; tags = $script:CurrentTags } }
        Mock New-GraphGetRequest -ParameterFilter { $Uri -like '*/applications?*' } -MockWith { }
        Mock New-GraphPOSTRequest -MockWith { }

        $Response = Invoke-ExecApplication -Request (New-Request $Action)

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results.state | Should -Be 'success'
        $ExpectedBody = '{"tags":' + $Expected + '}'
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'PATCH' -and $Body -eq $ExpectedBody -and
            $Uri -eq 'https://graph.microsoft.com/beta/servicePrincipals/00000000-0000-0000-0000-0000000000a1'
        }
    }

    It '<_> is refused on an app registration without touching Graph' -ForEach @('ShowInEnterpriseApps', 'HideFromEnterpriseApps') {
        Mock New-GraphGetRequest -MockWith { }
        Mock New-GraphPOSTRequest -MockWith { }

        $Response = Invoke-ExecApplication -Request (New-Request $_ 'applications')

        $Response.StatusCode | Should -Be 400
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It '<Action> is refused when the app registration carries <Tag>' -ForEach @(
        @{ Action = 'HideFromEnterpriseApps'; Tag = 'WindowsAzureActiveDirectoryIntegratedApp' }
        @{ Action = 'Show'; Tag = 'HideApp' }
    ) {
        $script:Tag = $Tag
        Mock New-GraphGetRequest -MockWith { [pscustomobject]@{ appId = '00000000-0000-0000-0000-0000000000ff'; displayName = 'Contoso App'; tags = @($script:Tag) } }
        Mock New-GraphGetRequest -ParameterFilter { $Uri -like '*/applications?*' } -MockWith { [pscustomobject]@{ id = 'app'; tags = @($script:Tag) } }
        Mock New-GraphPOSTRequest -MockWith { }

        $Response = Invoke-ExecApplication -Request (New-Request $Action)

        $Response.StatusCode | Should -Be 400
        @($Response.Body.Results)[0].resultText | Should -Match 'app registration'
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'adding a tag does not read the app registration' {
        Mock New-GraphGetRequest -MockWith { [pscustomobject]@{ appId = '00000000-0000-0000-0000-0000000000ff'; displayName = 'Contoso App'; tags = @() } }
        Mock New-GraphPOSTRequest -MockWith { }

        $null = Invoke-ExecApplication -Request (New-Request 'ShowInEnterpriseApps')

        Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $Uri -like '*/applications?*' }
    }

    It 'returns 500 without a success result when Graph rejects the change' {
        Mock New-GraphGetRequest -MockWith { [pscustomobject]@{ appId = '00000000-0000-0000-0000-0000000000ff'; displayName = 'Contoso App'; tags = @() } }
        Mock New-GraphPOSTRequest -MockWith { throw 'Insufficient privileges' }

        $Response = Invoke-ExecApplication -Request (New-Request 'ShowInEnterpriseApps')

        $Response.StatusCode | Should -Be 500
        @($Response.Body.Results)[0].state | Should -Be 'error'
    }
}
