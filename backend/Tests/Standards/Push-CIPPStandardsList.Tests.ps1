# Editing a standards template changes its StandardsTemplateV2 timestamp. Every Intune policy in that template
# must be re-applied, but the per-tenant cached timestamp used to be updated while checking the first policy,
# so the remaining policies compared against the new value and were skipped as compliant.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPStandards { [CmdletBinding()] param($TenantFilter, $RunManually, $TemplateId) }
    function Test-CIPPStandardLicense { [CmdletBinding()] param($StandardName, $TenantFilter, $Preset) }
    function Get-CippTable { [CmdletBinding()] param($TableName) }
    function Get-CIPPAzDataTableEntity { [CmdletBinding()] param($Table, $Filter) }
    function Add-CIPPAzDataTableEntity { [CmdletBinding()] param($Table, $Entity, [switch]$Force) }
    function New-GraphBulkRequest { [CmdletBinding()] param($Requests, $TenantId, $NoPaginateIds) }
    function Get-CIPPTenantAlignment { [CmdletBinding()] param($TenantFilter) }
    function Test-CIPPRerun { [CmdletBinding()] param([switch]$ClearAll, $TenantFilter, $Type) }

    . (Join-Path $RepoRoot 'Modules/CIPPActivityTriggers/Public/Entrypoints/Activity Triggers/Standards/Push-CIPPStandardsList.ps1')
}

Describe 'Push-CIPPStandardsList Intune template change decisions' {
    BeforeEach {
        $script:Tenant = 'contoso.onmicrosoft.com'
        $script:OldTimestamp = '2026-10-27T12:00:00Z'
        $script:NewTimestamp = '2026-10-28T12:00:00Z'
        $script:Standards = @(
            foreach ($PolicyId in @('policy-a', 'policy-b')) {
                [PSCustomObject]@{
                    Tenant     = $script:Tenant
                    Standard   = 'IntuneTemplate'
                    TemplateId = 'standard-a'
                    Settings   = @{ TemplateList = @{ value = $PolicyId }; remediate = $true; report = $true }
                }
            }
        )
        $script:Templates = @{
            'StandardsTemplateV2|standard-a' = @{ Timestamp = $script:NewTimestamp }
            'IntuneTemplate|policy-a'       = @{ JSON = '{"Type":"Device","Displayname":"Policy A"}' }
            'IntuneTemplate|policy-b'       = @{ JSON = '{"Type":"Device","Displayname":"Policy B"}' }
        }
        $script:Tracking = @{
            "$($script:Tenant)|Device" = @{
                LatestPolicyModified = $script:OldTimestamp
                LatestPolicyId       = 'graph-a'
                PolicyCount          = 2
            }
            "$($script:Tenant)|StandardTemplate_standard-a" = @{ CachedTimestamp = $script:OldTimestamp }
        }
        $script:GraphPolicies = @(
            @{ id = 'graph-a'; displayName = 'Policy A'; lastModifiedDateTime = $script:OldTimestamp }
            @{ id = 'graph-b'; displayName = 'Policy B'; lastModifiedDateTime = $script:OldTimestamp }
        )
        $script:Alignment = @{
            ComparisonDetails = @(
                @{ StandardName = 'standards.IntuneTemplate.policy-a'; Compliant = $true }
                @{ StandardName = 'standards.IntuneTemplate.policy-b'; Compliant = $true }
            )
        }
        $script:Item = @{ TenantFilter = $script:Tenant; runManually = $false }

        Mock Get-CIPPStandards { $script:Standards }
        Mock Test-CIPPStandardLicense { $true }
        Mock Get-CippTable { @{ Table = $TableName } }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -notmatch "^PartitionKey eq '([^']+)' and RowKey eq '([^']+)'$") {
                throw "Unexpected table filter: $Filter"
            }
            $RowKey = "$($Matches[1])|$($Matches[2])"
            switch ($Table) {
                'templates' { return $script:Templates[$RowKey] }
                'IntunePolicyTypeTracking' { return $script:Tracking[$RowKey] }
                default { throw "Unexpected table: $Table" }
            }
        }
        Mock Add-CIPPAzDataTableEntity {
            if ($Table -ne 'IntunePolicyTypeTracking' -or -not $Force) {
                throw 'Expected a forced tracking upsert'
            }
            # A subsequent read sees the write immediately, as it does in table storage.
            $script:Tracking["$($Entity.PartitionKey)|$($Entity.RowKey)"] = $Entity.Clone()
        }
        Mock New-GraphBulkRequest { @{ id = 'Device'; body = @{ value = $script:GraphPolicies } } }
        Mock Get-CIPPTenantAlignment { $script:Alignment }
        Mock Test-CIPPRerun { }
        Mock Write-Warning { }
        Mock Write-Host { }
    }

    AfterEach {
        Should -Invoke Write-Warning -Times 0 -Exactly
    }

    It 'keeps both policies sharing a changed template with input order <PolicyOrder>' -TestCases @(
        @{ PolicyOrder = @('policy-a', 'policy-b') }
        @{ PolicyOrder = @('policy-b', 'policy-a') }
    ) {
        param($PolicyOrder)
        $script:Standards = foreach ($PolicyId in $PolicyOrder) {
            $script:Standards | Where-Object { $_.Settings.TemplateList.value -eq $PolicyId }
        }

        $Result = @(Push-CIPPStandardsList -Item $script:Item)

        @($Result.Settings.TemplateList.value | Sort-Object) | Should -Be @('policy-a', 'policy-b')
        @($Result.FunctionName) | Should -Be @('CIPPStandard', 'CIPPStandard')
        $script:Tracking["$($script:Tenant)|StandardTemplate_standard-a"].CachedTimestamp | Should -Be $script:NewTimestamp
    }

    It 'skips unchanged, existing, previously compliant policies' {
        $script:Tracking["$($script:Tenant)|StandardTemplate_standard-a"].CachedTimestamp = $script:NewTimestamp

        @(Push-CIPPStandardsList -Item $script:Item).Count | Should -Be 0
    }

    It 'decides independently for policies in different standards templates' {
        ($script:Standards | Where-Object { $_.Settings.TemplateList.value -eq 'policy-b' }).TemplateId = 'standard-b'
        $script:Templates['StandardsTemplateV2|standard-b'] = @{ Timestamp = $script:NewTimestamp }
        $script:Tracking["$($script:Tenant)|StandardTemplate_standard-b"] = @{ CachedTimestamp = $script:NewTimestamp }

        $Result = @(Push-CIPPStandardsList -Item $script:Item)

        $Result.Count | Should -Be 1
        $Result[0].Settings.TemplateList.value | Should -Be 'policy-a'
    }

    It 'rechecks changes on later invocations instead of retaining the previous decision' {
        @(Push-CIPPStandardsList -Item $script:Item).Count | Should -Be 2
        @(Push-CIPPStandardsList -Item $script:Item).Count | Should -Be 0

        $script:Templates['StandardsTemplateV2|standard-a'].Timestamp = '2026-10-29T12:00:00Z'
        @(Push-CIPPStandardsList -Item $script:Item).Count | Should -Be 2
    }
}
