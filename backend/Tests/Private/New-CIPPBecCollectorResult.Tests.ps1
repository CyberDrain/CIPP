BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/New-CIPPBecCollectorResult.ps1')
}

Describe 'New-CIPPBecCollectorResult' {
    It 'defaults to a complete, non-skipped result' {
        $R = New-CIPPBecCollectorResult -Data @(1, 2, 3)
        $R.Complete | Should -BeTrue
        $R.Skipped | Should -BeFalse
        $R.Requirement | Should -BeNullOrEmpty
        $R.Error | Should -BeNullOrEmpty
        $R.Count | Should -Be 3
    }

    It 'marks a licence/permission gap as skipped, not complete and not a pass' {
        $R = New-CIPPBecCollectorResult -Data @() -Skipped $true -Requirement 'Entra ID P2'
        $R.Skipped | Should -BeTrue
        # A skipped check has not seen everything, so it is never complete...
        $R.Complete | Should -BeFalse
        $R.Requirement | Should -Be 'Entra ID P2'
        # ...and it carries no rows, so the UI cannot read it as a clean pass.
        $R.Count | Should -Be 0
    }

    It 'a hard failure is an error, distinct from a skip' {
        $R = New-CIPPBecCollectorResult -Data @() -Error 'boom'
        $R.Complete | Should -BeFalse
        $R.Skipped | Should -BeFalse
        $R.Error | Should -Be 'boom'
    }
}
