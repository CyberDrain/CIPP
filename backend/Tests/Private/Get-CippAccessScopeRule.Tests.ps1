# Pester tests for Get-CippAccessScopeRule / Expand-CippScopeTenantItem: a tenant group on the
# blocked side that cannot be expanded must fail closed (throw, nothing cached), never drop the block.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AuthDir = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication'

    function Get-CippAccessScopeVersion { 'v1' }
    function Get-CIPPRolePermissions { param($Role) }
    function Expand-CIPPTenantGroups { param($TenantFilter) }

    . (Join-Path $AuthDir 'Get-CippAccessScopeRule.ps1')
    . (Join-Path $AuthDir 'Expand-CippScopeTenantItem.ps1')

    $script:Group = { param($Id) [pscustomobject]@{ type = 'Group'; value = $Id; label = "Group $Id" } }
    $script:Member = { param($Id) [pscustomobject]@{ addedFields = [pscustomobject]@{ customerId = $Id } } }
}

Describe 'Get-CippAccessScopeRule tenant group expansion' {
    BeforeEach {
        $script:CippAccessScopeRuleCache = @{}
    }

    It 'throws and caches nothing when a blocked group cannot be expanded' {
        Mock Get-CIPPRolePermissions { [pscustomobject]@{ AllowedTenants = @('AllTenants'); BlockedTenants = @((& $script:Group 'gb')) } }
        Mock Expand-CIPPTenantGroups { throw 'table unavailable' }

        { Get-CippAccessScopeRule -Role 'blocker' } | Should -Throw -ExpectedMessage "*Failed to expand blocked tenant group 'Group gb'*"
        $script:CippAccessScopeRuleCache.Count | Should -Be 0

        # Once the lookup recovers the next call resolves the block instead of serving a cached failure
        Mock Expand-CIPPTenantGroups { & $script:Member 'tenant-9' }
        (Get-CippAccessScopeRule -Role 'blocker').BlockedTenants | Should -Be @('tenant-9')
    }

    It 'keeps an allowed group that cannot be expanded as contributing nothing' {
        Mock Get-CIPPRolePermissions { [pscustomobject]@{ AllowedTenants = @('tenant-1', (& $script:Group 'ga')); BlockedTenants = @() } }
        Mock Expand-CIPPTenantGroups { throw 'table unavailable' }

        $Rule = Get-CippAccessScopeRule -Role 'allower' -WarningAction SilentlyContinue
        $Rule.AllowedTenants | Should -Be @('tenant-1')
        $Rule.AllowedGroups | Should -Be @('ga')
    }

    It 'treats a blocked group that expands to no members (deleted) as blocking nothing' {
        Mock Get-CIPPRolePermissions { [pscustomobject]@{ AllowedTenants = @('AllTenants'); BlockedTenants = @((& $script:Group 'gone')) } }
        Mock Expand-CIPPTenantGroups { }

        $Rule = Get-CippAccessScopeRule -Role 'deleted'
        $Rule.AllowAllTenants | Should -BeTrue
        @($Rule.BlockedTenants).Count | Should -Be 0
    }
}
