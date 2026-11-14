# Pester tests for the "Copy OneDrive to user(s)" option in Invoke-CIPPOffboardingJob:
# - off: the batch is exactly what it was before the option existed
# - on: the copy step runs before licence removal, and licence removal waits for the copy

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $JobPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPOffboardingJob.ps1'
    $HtmlPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPHtmlIsEmpty.ps1'
    $ValidatorPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPOffboardingRequest.ps1'

    function New-GraphGetRequest { param($uri, $tenantid) }
    function Get-CIPPTextReplacement { param($TenantFilter, $Text, [switch]$EscapeForJson) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $headers, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Write-Information { param($MessageData) }

    . $HtmlPath
    . $JobPath
    . $ValidatorPath

    function Get-Batch($Options) {
        $null = Invoke-CIPPOffboardingJob -TenantFilter 'contoso.com' -Username 'pat@contoso.com' -Options ([pscustomobject]$Options)
        @($script:CapturedInput.Batch)
    }
}

Describe 'Invoke-CIPPOffboardingJob OneDrive copy' {
    BeforeEach {
        $script:CapturedInput = $null
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Write-Information -MockWith { }
        Mock -CommandName Get-CIPPTextReplacement -MockWith { $Text }
        Mock -CommandName New-GraphGetRequest -MockWith {
            [pscustomobject]@{ id = 'aaaaaaaa-1111-2222-3333-444444444444'; displayName = 'Pat Lee'; onPremisesSyncEnabled = $false; onPremisesImmutableId = $null }
        }
        Mock -CommandName Start-CIPPOrchestrator -MockWith { $script:CapturedInput = $InputObject; 'orch-1' }
    }

    It 'leaves the batch unchanged when the option is <Case>' -ForEach @(
        @{ Case = 'absent'; Extra = @{} }
        @{ Case = 'empty'; Extra = @{ OneDriveCopyTo = @() } }
        @{ Case = 'null'; Extra = @{ OneDriveCopyTo = $null } }
    ) {
        $Options = @{ RemoveLicenses = $true; DisableSignIn = $true; OnedriveAccess = @(@{ value = 'helper-id-1' }) } + $Extra
        $Batch = Get-Batch $Options
        @($Batch | ForEach-Object { $_.Cmdlet }) | Should -Be @('Set-CIPPSignInState', 'Set-CIPPSharePointPerms', 'Remove-CIPPLicense')
        ($Batch | Where-Object Cmdlet -EQ 'Remove-CIPPLicense').Title | Should -Be 'Remove licenses'
        ($Batch | Where-Object Cmdlet -EQ 'Remove-CIPPLicense').Parameters.Schedule | Should -BeTrue
    }

    It 'copies before removing licences, and removes them through the copy gate' {
        $Batch = Get-Batch @{ RemoveLicenses = $true; DisableSignIn = $true; OneDriveCopyTo = @(@{ label = 'Bob'; value = 'bob-id' }, 'carol@contoso.com') }
        $Cmdlets = @($Batch | ForEach-Object { $_.Cmdlet })

        $Cmdlets | Should -Not -Contain 'Remove-CIPPLicense'
        $Cmdlets.IndexOf('Invoke-CIPPOffboardingOneDriveCopy') | Should -BeLessThan $Cmdlets.IndexOf('Remove-CIPPLicenseAfterOneDriveCopy')
        $script:CapturedInput.Sequential | Should -BeTrue

        $Copy = $Batch | Where-Object Cmdlet -EQ 'Invoke-CIPPOffboardingOneDriveCopy'
        $Copy.Title | Should -Be 'Copy OneDrive to user(s)'
        $Copy.Parameters.Username | Should -Be 'pat@contoso.com'
        $Copy.Parameters.TenantFilter | Should -Be 'contoso.com'
        @($Copy.Parameters.Recipients).Count | Should -Be 2

        $Gate = $Batch | Where-Object Cmdlet -EQ 'Remove-CIPPLicenseAfterOneDriveCopy'
        $Gate.Parameters.userid | Should -Be 'aaaaaaaa-1111-2222-3333-444444444444'
        # Both steps carry the same operation id, so the gate waits for exactly this run's copy.
        $Copy.Parameters.OperationId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
        $Gate.Parameters.CopyOperationId | Should -Be $Copy.Parameters.OperationId
        $Gate.Parameters.ContainsKey('CopyStartedAfter') | Should -BeFalse
    }

    It 'copies without touching licences when Remove licenses is off' {
        $Cmdlets = @(Get-Batch @{ DisableSignIn = $true; OneDriveCopyTo = @('bob@contoso.com') } | ForEach-Object { $_.Cmdlet })
        $Cmdlets | Should -Be @('Set-CIPPSignInState', 'Invoke-CIPPOffboardingOneDriveCopy')
    }

    It 'skips the copy when the user is being deleted, like every other non-delete step' {
        $Cmdlets = @(Get-Batch @{ DeleteUser = $true; OneDriveCopyTo = @('bob@contoso.com') } | ForEach-Object { $_.Cmdlet })
        $Cmdlets | Should -Be @('Remove-CIPPUser')
    }

    It 'the validator accepts the copy as the only selected action' {
        function Test-CIPPHtmlIsEmpty { param($Html) $true }
        $Result = Test-CIPPOffboardingRequest -Body ([pscustomobject]@{ tenantFilter = 'contoso.com'; user = @(@{ value = 'pat@contoso.com' }); OneDriveCopyTo = @(@{ value = 'bob-id' }); DisableSignIn = $true })
        $Result.IsValid | Should -BeTrue
    }
    It 'runs the copy after Disable sign in' {
        $Cmdlets = @(Get-Batch @{ RemoveLicenses = $true; DisableSignIn = $true; RevokeSessions = $true; OneDriveCopyTo = @('bob@contoso.com') } | ForEach-Object { $_.Cmdlet })
        $Cmdlets.IndexOf('Set-CIPPSignInState') | Should -BeLessThan $Cmdlets.IndexOf('Invoke-CIPPOffboardingOneDriveCopy')
        $Cmdlets.IndexOf('Invoke-CIPPOffboardingOneDriveCopy') | Should -BeLessThan $Cmdlets.IndexOf('Remove-CIPPLicenseAfterOneDriveCopy')
    }

    It 'the validator refuses the copy without Disable sign in' -ForEach @(
        @{ Extra = @{} }
        @{ Extra = @{ DisableSignIn = $false } }
    ) {
        function Test-CIPPHtmlIsEmpty { param($Html) $true }
        $Body = @{ tenantFilter = 'contoso.com'; user = @(@{ value = 'pat@contoso.com' }); OneDriveCopyTo = @(@{ value = 'bob-id' }); RemoveLicenses = $true } + $Extra
        $Result = Test-CIPPOffboardingRequest -Body ([pscustomobject]$Body)
        $Result.IsValid | Should -BeFalse
        $Result.Errors | Should -BeLike "*'OneDriveCopyTo' needs 'DisableSignIn'*"
    }

    It 'the validator is unchanged when the copy is not selected' {
        function Test-CIPPHtmlIsEmpty { param($Html) $true }
        (Test-CIPPOffboardingRequest -Body ([pscustomobject]@{ tenantFilter = 'contoso.com'; user = @(@{ value = 'pat@contoso.com' }); RemoveLicenses = $true; OneDriveCopyTo = @() })).IsValid | Should -BeTrue
    }
}
