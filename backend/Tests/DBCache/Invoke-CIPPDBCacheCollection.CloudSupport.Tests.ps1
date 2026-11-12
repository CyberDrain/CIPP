# The nightly cache collection does not collect cache types a tenant's cloud does not support (redanthrax/CIPP#4):
# for a government tenant the Teams admin ConfigAPI types are left out with one informational log line, instead of a
# failure per type. A Commercial tenant collects the full list, as before, and nothing is logged.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:RepoRoot = $RepoRoot
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Invoke-CIPPDBCacheCollection.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPDBCacheSchedule.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPCloudFeatureSupport.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-CIPPCloudFeatureSupport.ps1')

    function Get-CIPPTenantRequestCloud { param($TenantFilter) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    $script:TeamsTypes = @('CsTeamsMeetingPolicy', 'CsTeamsClientConfiguration', 'CsExternalAccessPolicy', 'CsTenantFederationConfiguration',
        'CsTeamsMessagingPolicy', 'CsTeamsFilesPolicy', 'CsTeamsMessagingConfiguration', 'CsTeamsAppPermissionPolicy', 'Teams', 'TeamsActivity',
        'TeamsVoice', 'TeamsResourceAccounts')
    foreach ($Type in $script:TeamsTypes) {
        $null = New-Item -Path "function:script:Set-CIPPDBCache$Type" -Value ([scriptblock]::Create("param(`$TenantFilter, `$QueueId) `$script:Collected.Add('$Type')")) -Force
    }

    $script:PreviousRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $RepoRoot
}

AfterAll { $env:CIPPRootPath = $script:PreviousRoot }

Describe 'Invoke-CIPPDBCacheCollection cloud support' {
    BeforeEach {
        $script:CIPPCloudFeatureSupport = $null
        $script:Collected = [System.Collections.Generic.List[string]]::new()
        Mock Write-LogMessage {}
    }

    It 'collects every Teams cache type for a Commercial tenant and logs nothing' {
        Mock Get-CIPPTenantRequestCloud { 'Commercial' }
        Mock Get-CIPPCloudFeatureSupport {}
        $Result = Invoke-CIPPDBCacheCollection -CollectionType 'Teams' -TenantFilter 'contoso.onmicrosoft.com' 6>$null

        @($script:Collected) | Should -Be $script:TeamsTypes
        $Result.Total | Should -Be $script:TeamsTypes.Count
        $Result.Failed | Should -Be 0
        Should -Invoke Write-LogMessage -Times 0 -Exactly
        Should -Invoke Get-CIPPCloudFeatureSupport -Times 0 -Exactly
    }

    It 'leaves out the unsupported cache types for a government tenant with one informational log line' {
        Mock Get-CIPPTenantRequestCloud { 'USGovHigh' }
        $Result = Invoke-CIPPDBCacheCollection -CollectionType 'Teams' -TenantFilter 'gov.onmicrosoft.us' 6>$null

        @($script:Collected) | Should -Be @('Teams', 'TeamsActivity') -Because 'Graph-based Teams data is still collected'
        $Result.Failed | Should -Be 0
        Should -Invoke Write-LogMessage -Times 1 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Info' -and $message -like '*10 Teams cache type(s) not supported for USGovHigh*' }
    }

    It 'collects everything when the cloud cannot be resolved' {
        Mock Get-CIPPTenantRequestCloud { throw 'no marker' }
        $null = Invoke-CIPPDBCacheCollection -CollectionType 'Teams' -TenantFilter 'contoso.onmicrosoft.com' 6>$null
        @($script:Collected) | Should -Be $script:TeamsTypes
    }
}
