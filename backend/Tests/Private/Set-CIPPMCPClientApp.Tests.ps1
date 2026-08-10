# Pester tests for Set-CIPPMCPClientApp
# Verifies that the MCP resource is registered for every hostname bound to the instance (default
# *.azurewebsites.net plus custom domains, sourced from Get-CIPPSiteHostname), that existing
# identifier URIs are preserved (additive - no working connector breaks on upgrade), and that the
# previous WEBSITE_HOSTNAME behaviour is kept as a fallback when ARM discovery returns nothing.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Set-CIPPMCPClientApp.ps1'

    # Minimal stubs so Mock has commands to replace during tests
    function Get-CIPPSiteHostname { }
    function New-GraphGetRequest { param($uri, $NoAuthCheck, $AsApp) }
    function New-GraphPOSTRequest { param($uri, $type, $body, $NoAuthCheck, $asapp) }
    function Get-CippMcpKnownClients { }
    function Write-LogMessage { param($headers, $API, $message, $Sev) }

    . $FunctionPath
}

Describe 'Set-CIPPMCPClientApp' {
    BeforeEach {
        $script:PatchBody = $null
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CippMcpKnownClients -MockWith {
            [PSCustomObject]@{
                PreAuthorizedClientIds   = @()
                PublicClientRedirectUris = @()
                ConfidentialRedirectUris = @()
            }
        }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [PSCustomObject]@{
                id             = 'object-1'
                identifierUris = @('api://app-1')
                api            = $null
                web            = [PSCustomObject]@{ redirectUris = @('https://inst.azurewebsites.net/.auth/login/aad/callback') }
                spa            = [PSCustomObject]@{ redirectUris = @() }
                publicClient   = [PSCustomObject]@{ redirectUris = @() }
            }
        }
        # Capture the PATCH body the function would send to Graph
        Mock -CommandName New-GraphPOSTRequest -MockWith { $script:PatchBody = $body }
    }

    It 'registers MCP identifier URIs for every bound hostname, preserving existing ones' {
        Mock -CommandName Get-CIPPSiteHostname -MockWith { @('inst.azurewebsites.net', 'cipp.example.com') }

        Set-CIPPMCPClientApp -AppId 'app-1' -Confirm:$false

        $Uris = @(($script:PatchBody | ConvertFrom-Json).identifierUris)
        $Uris | Should -Contain 'api://app-1'                                  # existing preserved (additive)
        $Uris | Should -Contain 'https://inst.azurewebsites.net'               # default host
        $Uris | Should -Contain 'https://inst.azurewebsites.net/api/ExecMcp'
        $Uris | Should -Contain 'https://cipp.example.com'                     # custom domain
        $Uris | Should -Contain 'https://cipp.example.com/api/ExecMcp'
    }

    It 'falls back to WEBSITE_HOSTNAME when ARM discovery returns nothing' {
        Mock -CommandName Get-CIPPSiteHostname -MockWith { @() }
        $OldHost = $env:WEBSITE_HOSTNAME
        $env:WEBSITE_HOSTNAME = 'fallback.azurewebsites.net'
        try {
            Set-CIPPMCPClientApp -AppId 'app-1' -Confirm:$false

            $Uris = @(($script:PatchBody | ConvertFrom-Json).identifierUris)
            $Uris | Should -Contain 'https://fallback.azurewebsites.net'
            $Uris | Should -Contain 'https://fallback.azurewebsites.net/api/ExecMcp'
        } finally {
            $env:WEBSITE_HOSTNAME = $OldHost
        }
    }
}
