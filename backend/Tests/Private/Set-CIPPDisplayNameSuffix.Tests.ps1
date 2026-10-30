BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $CmdletPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Set-CIPPDisplayNameSuffix.ps1'

    function New-GraphPostRequest { param($uri, $tenantid, $type, $body) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . $CmdletPath
}

Describe 'Set-CIPPDisplayNameSuffix' {
    BeforeEach {
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName New-GraphPostRequest -MockWith { }
    }

    It 'appends the suffix after a space' {
        $null = Set-CIPPDisplayNameSuffix -UserID 'user-id-1' -DisplayName 'Pat Lee' -Suffix ' - Leaver ' -TenantFilter 'contoso.com'

        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter {
            $type -eq 'PATCH' -and $tenantid -eq 'contoso.com' -and ($body | ConvertFrom-Json).displayName -eq 'Pat Lee - Leaver'
        }
    }

    It 'does not append the suffix twice on a re-run' {
        $null = Set-CIPPDisplayNameSuffix -UserID 'user-id-1' -DisplayName 'Pat Lee - Leaver' -Suffix '- Leaver' -TenantFilter 'contoso.com'

        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
    }
}
