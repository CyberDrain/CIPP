BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:OriginalRoot = $env:CIPPRootPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/BEC/Get-CIPPBecHeuristics.ps1')
    $script:BackendRoot = $RepoRoot
}

AfterAll {
    $env:CIPPRootPath = $script:OriginalRoot
}

Describe 'Get-CIPPBecHeuristics' {
    BeforeEach {
        $env:CIPPRootPath = $script:BackendRoot
    }

    It 'loads the shipped heuristics file with every section present' {
        $H = Get-CIPPBecHeuristics -Force
        $H.window.days | Should -Be 7
        $H.score.weights.NewRules | Should -Be 3
        $H.score.thresholds.high | Should -Be 7
        $H.caps.auditLogPages | Should -BeGreaterThan 0
        @($H.highRiskAuditOperations).Count | Should -BeGreaterThan 5
        @($H.directoryAudit.flaggedActivities) | Should -Contain 'Consent to application'
        @($H.transportRules.operations) | Should -Contain 'New-TransportRule'
        $H.sentMail.repeatSubjectMessages | Should -Be 5
    }

    It 'ships only regexes that compile' {
        $H = Get-CIPPBecHeuristics -Force
        $Patterns = @(
            $H.inboxRules.lowVisibilityFolderRegex
            $H.inboxRules.sensitiveNameRegex
            $H.phishingKeywordPattern
            $H.riskyScopes.regex
            $H.transportRules.riskyParameterRegex
            $H.transportRules.descriptionRegex
            $H.mailboxAddIns.trustedProviderRegex
        ) + @($H.phishingSubjectPatterns.PSObject.Properties.Value)
        $Patterns.Count | Should -BeGreaterThan 10
        foreach ($Pattern in $Patterns) {
            { [regex]::new($Pattern) } | Should -Not -Throw -Because "'$Pattern' must be a valid .NET regex"
        }
    }

    It 'matches the IR-console fixtures with the shipped regexes' {
        $H = Get-CIPPBecHeuristics -Force
        'Mail.ReadWrite' | Should -Match $H.riskyScopes.regex
        'offline_access' | Should -Match $H.riskyScopes.regex
        'User.Read' | Should -Not -Match $H.riskyScopes.regex
        'BlindCopyTo' | Should -Match $H.transportRules.riskyParameterRegex
        'SubjectContainsWords' | Should -Not -Match $H.transportRules.riskyParameterRegex
        'RSS Subscriptions' | Should -Match $H.inboxRules.lowVisibilityFolderRegex
        'Urgent action required' | Should -Match $H.phishingSubjectPatterns.'Urgent action language'
    }

    It 'merges the delegated names from RiskyPermissions.json into catalogNames' {
        $H = Get-CIPPBecHeuristics -Force
        $H.riskyScopes.catalogNames | Should -Not -BeNullOrEmpty
        @($H.riskyScopes.catalogNames) | Should -Not -Contain 'RoleManagement.ReadWrite.Directory' -Because 'application permissions are not delegated scopes'
    }

    It 'memoises the parsed file and reloads on -Force' {
        $First = Get-CIPPBecHeuristics -Force
        $Second = Get-CIPPBecHeuristics
        [object]::ReferenceEquals($First, $Second) | Should -BeTrue
        $Third = Get-CIPPBecHeuristics -Force
        [object]::ReferenceEquals($First, $Third) | Should -BeFalse
    }

    It 'throws when the file is missing' {
        $env:CIPPRootPath = Join-Path $TestDrive 'nowhere'
        { Get-CIPPBecHeuristics -Force } | Should -Throw
    }
}
