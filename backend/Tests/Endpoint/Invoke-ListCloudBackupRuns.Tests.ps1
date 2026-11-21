BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')

    function New-RunRow {
        param($PolicyId = '11111111-1111-1111-1111-111111111111', $TenantId = 'c1', [datetime]$StartedAt, $Status = 'Succeeded', $Workload = 'exchange')
        [pscustomobject]@{
            PartitionKey    = $PolicyId
            RowKey          = '{0:D19}_{1}_{2}' -f ([datetime]::MaxValue.Ticks - $StartedAt.Ticks), $TenantId, $Workload
            PolicyId        = $PolicyId
            PolicyName      = 'Nightly'
            TenantId        = $TenantId
            Tenant          = "$TenantId.com"
            Workload        = $Workload
            Status          = $Status
            StartedAt       = $StartedAt.ToString('o')
            CompletedAt     = $StartedAt.AddSeconds(90).ToString('o')
            Owners          = 3
            OwnersSucceeded = 2
            OwnersFailed    = 1
            Items           = 12
            Bytes           = [int64]2048
            Deleted         = 2
            Warnings        = '["1 of 3 items failed or did not finish"]'
            Location        = "$PolicyId/$TenantId/$Workload/"
        }
    }
    function Invoke-Runs { param($Query) Invoke-ListCloudBackupRuns -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupRuns' -Query $Query) }
}

Describe 'Invoke-ListCloudBackupRuns' {
    BeforeEach {
        $script:Allowed = @('AllTenants')
        $Now = [datetime]::UtcNow
        $script:Runs = @{
            '11111111-1111-1111-1111-111111111111' = @((New-RunRow -StartedAt $Now.AddHours(-1)), (New-RunRow -TenantId 'c2' -StartedAt $Now.AddHours(-3) -Status 'Failed'))
            '33333333-3333-3333-3333-333333333333' = @((New-RunRow -PolicyId '33333333-3333-3333-3333-333333333333' -StartedAt $Now.AddHours(-2)))
        }
        Mock Test-CIPPAccess { $script:Allowed }
        Mock Get-Tenants { $script:CloudBackupTenants }
        Mock Get-CIPPAzDataTableEntity { @(New-CloudBackupPolicyRow; New-CloudBackupPolicyRow -Id '33333333-3333-3333-3333-333333333333') } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity {
            $Partition = ([regex]::Match($Filter, "PartitionKey eq '([^']+)'")).Groups[1].Value
            $Rows = @($script:Runs[$Partition])
            if ($Filter -match "TenantId eq '([^']+)'") { $Tenant = $Matches[1]; $Rows = @($Rows.Where({ $_.TenantId -eq $Tenant })) }
            if ($Filter -match "Workload eq '([^']+)'") { $Name = $Matches[1]; $Rows = @($Rows.Where({ $_.Workload -eq $Name })) }
            $Rows
        } -ParameterFilter { $TableName -eq 'CloudBackupRuns' }
        Mock Write-LogMessage { }
    }

    It 'merges every policy newest first and shapes each run' {
        $Response = Invoke-Runs

        $Response.StatusCode | Should -Be 200
        $Rows = @($Response.Body)
        @($Rows.PolicyId) | Should -Be @('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111')
        $Rows[0].DurationSeconds | Should -Be 90
        $Rows[0].Workload | Should -Be 'exchange'
        $Rows[0].OwnerCount | Should -Be 3
        $Rows[0].SucceededOwners | Should -Be 2
        $Rows[0].FailedOwners | Should -Be 1
        $Rows[0].Deleted | Should -Be 2
        @($Rows[0].Warnings) | Should -Be @('1 of 3 items failed or did not finish')
        $Rows[0].PSObject.Properties['Areas'] | Should -BeNullOrEmpty
        $Rows[0].Bytes | Should -Be 2048
        $Rows[0].Id | Should -BeLike '11111111-1111-1111-1111-111111111111_*'
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'CloudBackupRuns' -and $First -eq 1000 }
    }

    It 'filters by policy and tenant' {
        $Rows = @((Invoke-Runs -Query @{ PolicyId = '11111111-1111-1111-1111-111111111111'; tenantFilter = 'fabrikam.com' }).Body)
        $Rows.Count | Should -Be 1
        $Rows[0].TenantId | Should -Be 'c2'
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $Filter -eq "PartitionKey eq '11111111-1111-1111-1111-111111111111' and TenantId eq 'c2'" }
    }

    It 'filters by workload and refuses an unknown workload' {
        $script:Runs['11111111-1111-1111-1111-111111111111'] = @((New-RunRow -StartedAt ([datetime]::UtcNow.AddHours(-1))), (New-RunRow -StartedAt ([datetime]::UtcNow.AddHours(-2)) -Workload 'teams'))

        $Rows = @((Invoke-Runs -Query @{ PolicyId = '11111111-1111-1111-1111-111111111111'; Workload = 'Teams' }).Body)
        $Rows.Count | Should -Be 1
        $Rows[0].Workload | Should -Be 'teams'
        (Invoke-Runs -Query @{ Workload = 'config' }).StatusCode | Should -Be 400
    }

    It 'returns only runs for the tenants a restricted caller can access' {
        $script:Allowed = @('c2')
        @((Invoke-Runs).Body.TenantId) | Should -Be @('c2')
    }

    It 'returns 400 for a bad policy id and 404 for an unknown tenant' {
        (Invoke-Runs -Query @{ PolicyId = 'x' }).StatusCode | Should -Be 400
        (Invoke-Runs -Query @{ tenantFilter = 'unknown.com' }).StatusCode | Should -Be 404
    }
}

Describe 'Invoke-ListCloudBackupOverview' {
    BeforeEach {
        $script:Allowed = @('AllTenants')
        $Now = [datetime]::UtcNow
        Mock Test-CIPPAccess { $script:Allowed }
        Mock Get-Tenants { $script:CloudBackupTenants }
        Mock Get-CIPPCloudBackupDestination { @([pscustomobject]@{ RowKey = 'd1' }, [pscustomobject]@{ RowKey = 'd2' }) }
        Mock Get-CIPPAzDataTableEntity {
            @(
                New-CloudBackupPolicyRow -Tenants '[{"type":"Tenant","customerId":"c1"},{"type":"Tenant","customerId":"c2"}]'
                New-CloudBackupPolicyRow -Id '33333333-3333-3333-3333-333333333333' -Enabled $false -Tenants '[{"type":"Tenant","customerId":"c3"}]'
            )
        } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like "*11111111*") {
                $Rows = @(
                    New-RunRow -TenantId 'c1' -StartedAt $Now.AddHours(-1)
                    New-RunRow -TenantId 'c2' -StartedAt $Now.AddHours(-2) -Status 'Failed'
                    New-RunRow -TenantId 'c1' -StartedAt $Now.AddHours(-20) -Status 'Failed'
                    New-RunRow -TenantId 'c1' -StartedAt $Now.AddHours(-3) -Workload 'onedrive'
                )
                if ($Filter -match "TenantId eq '([^']+)'") { $Tenant = $Matches[1]; $Rows = $Rows.Where({ $_.TenantId -eq $Tenant }) }
                $Rows
            }
        } -ParameterFilter { $TableName -eq 'CloudBackupRuns' }
        Mock Write-LogMessage { }
    }

    It 'summarises policies, coverage, failures and the latest run per policy and tenant' {
        $Response = Invoke-ListCloudBackupOverview -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupOverview')

        $Response.StatusCode | Should -Be 200
        $Body = $Response.Body
        $Body.Policies | Should -Be 2
        $Body.EnabledPolicies | Should -Be 1
        $Body.Destinations | Should -Be 2
        $Body.TenantsCovered | Should -Be 2
        $Body.Failures24h | Should -Be 2
        $Body.LatestRuns.Count | Should -Be 3
        @($Body.LatestRuns.Where({ $_.Workload -eq 'exchange' }) | Sort-Object TenantId).Status | Should -Be @('Succeeded', 'Failed')
        $Body.LatestBytes | Should -Be 6144
        $Exchange = $Body.Workloads.Where({ $_.Workload -eq 'exchange' })[0]
        $Exchange.Policies | Should -Be 1
        $Exchange.Tenants | Should -Be 2
        $Exchange.Failures24h | Should -Be 2
        $Exchange.Bytes | Should -Be 4096
        $Exchange.OwnerCount | Should -Be 6
        $Exchange.LastRunStatus | Should -Be 'Succeeded'
        @($Body.LatestRuns.Workload | Sort-Object -Unique) | Should -Be @('exchange', 'onedrive')
        $OneDrive = $Body.Workloads.Where({ $_.Workload -eq 'onedrive' })[0]
        $OneDrive.Tenants | Should -Be 1
        $OneDrive.Items | Should -Be 12
        @($Body.Workloads.Workload) | Should -Be @('exchange', 'onedrive', 'sharepoint', 'teams')
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'CloudBackupRuns' -and $Property -contains 'RowKey' -and $Filter -match "RowKey lt '\d{19}'" }
    }

    It 'limits a restricted caller to policies and runs of their tenants' {
        $script:Allowed = @('c3')

        $Body = (Invoke-ListCloudBackupOverview -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupOverview')).Body
        $Body.Policies | Should -Be 1
        $Body.TenantsCovered | Should -Be 0
        $Body.LatestRuns.Count | Should -Be 0
    }

    It 'summarises only the selected tenant' {
        $Body = (Invoke-ListCloudBackupOverview -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupOverview' -Query @{ tenantFilter = 'fabrikam.com' })).Body
        $Body.Policies | Should -Be 1
        $Body.TenantsCovered | Should -Be 1
        $Body.Failures24h | Should -Be 1
        @($Body.LatestRuns.TenantId) | Should -Be @('c2')
        $Body.Destinations | Should -Be 2

        (Invoke-ListCloudBackupOverview -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupOverview' -Query @{ tenantFilter = 'AllTenants' })).Body.TenantsCovered | Should -Be 2
        (Invoke-ListCloudBackupOverview -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupOverview' -Query @{ tenantFilter = 'unknown.com' })).StatusCode | Should -Be 404
    }
}
