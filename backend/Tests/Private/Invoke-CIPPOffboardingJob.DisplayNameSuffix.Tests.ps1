BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $JobPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPOffboardingJob.ps1'
    $HtmlPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPHtmlIsEmpty.ps1'

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-Information { param($MessageData) }

    . $HtmlPath
    . $JobPath
}

Describe 'Invoke-CIPPOffboardingJob display name suffix' {
    BeforeEach {
        $script:CapturedInput = $null
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-Information -MockWith { }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ id = 'user-id-1'; displayName = 'Pat Lee'; onPremisesSyncEnabled = $false; onPremisesImmutableId = $null }
        }
        Mock -CommandName Start-CIPPOrchestrator -MockWith {
            $script:CapturedInput = $InputObject
            'orch-1'
        }
    }

    It 'uses - Leaver when the switch is on and no suffix is given' {
        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options ([pscustomobject]@{ AddDisplayNameSuffix = $true })

        $Task = $script:CapturedInput.Batch | Where-Object { $_.Cmdlet -eq 'Set-CIPPDisplayNameSuffix' }
        $Task.Parameters.Suffix | Should -Be '- Leaver'
        $Task.Parameters.UserID | Should -Be 'pat@contoso.com'
    }

    It 'uses the given suffix' {
        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options ([pscustomobject]@{ AddDisplayNameSuffix = $true; DisplayNameSuffix = '(Left)' })

        ($script:CapturedInput.Batch | Where-Object { $_.Cmdlet -eq 'Set-CIPPDisplayNameSuffix' }).Parameters.Suffix | Should -Be '(Left)'
    }

    It 'skips the rename when the switch is off, even with a suffix saved' {
        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options ([pscustomobject]@{ DisplayNameSuffix = '- Leaver'; RevokeSessions = $true })

        $script:CapturedInput.Batch.Cmdlet | Should -Not -Contain 'Set-CIPPDisplayNameSuffix'
    }
}
