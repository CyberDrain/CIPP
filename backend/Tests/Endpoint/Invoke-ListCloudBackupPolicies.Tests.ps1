BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    function Invoke-List { param($Query) Invoke-ListCloudBackupPolicies -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupPolicies' -Query $Query) }
}

Describe 'Invoke-ListCloudBackupPolicies' {
    BeforeEach {
        $script:Allowed = @('AllTenants')
        $script:PolicyRows = @(
            New-CloudBackupPolicyRow -Tenants '[{"type":"Tenant","customerId":"c1"},{"type":"Group","id":"g1"}]'
            New-CloudBackupPolicyRow -Id '33333333-3333-3333-3333-333333333333' -Name 'Everyone' -Tenants '[{"type":"AllTenants"}]'
        )
        Mock Test-CIPPAccess { $script:Allowed }
        Mock Get-Tenants { $script:CloudBackupTenants }
        Mock Get-TenantGroups { [pscustomobject]@{ Id = 'g1'; Name = 'EU customers' } }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -match "RowKey eq '([^']+)'") { $Key = $Matches[1]; @($script:PolicyRows).Where({ $_.RowKey -eq $Key }) } else { $script:PolicyRows }
        } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = '11111111-1111-1111-1111-111111111111'; RowKey = '1_c1'; Status = 'Succeeded'; StartedAt = '2026-11-19T00:00:00.0000000Z' } } -ParameterFilter { $TableName -eq 'CloudBackupRuns' -and $Filter -like '*11111111*' }
        Mock Get-CIPPAzDataTableEntity { } -ParameterFilter { $TableName -eq 'CloudBackupRuns' -and $Filter -notlike '*11111111*' }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ RowKey = '22222222-2222-2222-2222-222222222222'; Name = 'Blob'; Provider = 'AzureBlob' } }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -like '*11111111*') {
                [pscustomobject]@{ PartitionKey = '11111111-1111-1111-1111-111111111111'; RowKey = 'c1'; Status = 'Failed'; Message = 'Insufficient privileges'; CheckedAt = '2026-11-19T00:00:00.0000000Z' }
            }
        } -ParameterFilter { $TableName -eq 'CloudBackupPermissions' }
    }

    It 'returns Tenants in the tenant selector shape the policy form posts back' {
        $Response = Invoke-List

        $Response.StatusCode | Should -Be 200
        $Rows = @($Response.Body)
        $Rows.Count | Should -Be 2
        $Tenants = $Rows[0].Tenants
        $Tenants[0].label | Should -Be 'Contoso (contoso.com)'
        $Tenants[0].value | Should -Be 'contoso.com'
        $Tenants[0].type | Should -Be 'Tenant'
        $Tenants[0].addedFields.customerId | Should -Be 'c1'
        $Tenants[1].label | Should -Be 'EU customers'
        $Tenants[1].value | Should -Be 'g1'
        $Tenants[1].type | Should -Be 'Group'
        $Rows[0].TenantSummary | Should -Be 'Contoso (contoso.com), EU customers'
        $Rows[0].DestinationName | Should -Be 'Blob'
        $Rows[0].Provider | Should -Be 'AzureBlob'
        $Rows[0].LastRunStatus | Should -Be 'Succeeded'
        $Rows[0].LastRunAt | Should -Be '2026-11-19T00:00:00.0000000Z'
        @($Rows[0].Workloads) | Should -Be @('exchange', 'onedrive')
        $Rows[0].Schedules.exchange | Should -Be '4h'
        $Rows[0].NextRuns.onedrive | Should -Be '2026-01-01T00:00:00.0000000Z'
        @($Rows[0].Exclusions.Users).Count | Should -Be 0
        $Rows[0].PermissionStatus.c1.Status | Should -Be 'Failed'
        $Rows[0].PermissionStatus.c1.Message | Should -Be 'Insufficient privileges'
        $Rows[0].PermissionStatus.c1.Tenant | Should -Be 'contoso.com'
        @($Rows[1].PermissionStatus.PSObject.Properties).Count | Should -Be 0
        $Rows[1].Tenants[0].value | Should -Be 'AllTenants'
        $Rows[1].Tenants[0].type | Should -Be 'Tenant'
        $Rows[1].TenantSummary | Should -Be 'All tenants'
        $Rows[1].LastRunStatus | Should -BeNullOrEmpty
    }

    It 'round-trips through ExecCloudBackupPolicy to the same stored tenants' {
        $Listed = @((Invoke-List).Body)[0]
        $script:Saved = $null
        Mock Add-CIPPAzDataTableEntity { $script:Saved = $Entity } -ParameterFilter { $TableName -eq 'Config' }
        Mock Add-CIPPAzDataTableEntity { } -ParameterFilter { $TableName -eq 'CloudBackupPermissions' }
        Mock Set-CIPPCloudBackupRetentionRule { }
        Mock Get-CIPPCloudBackupVersioning { 'Enabled' }
        Mock Expand-CIPPTenantGroups { }
        Mock Start-CIPPOrchestrator { }
        Mock Write-LogMessage { }
        $Body = @{
            Action = 'Edit'; Id = $Listed.Id; Name = $Listed.Name; Enabled = $Listed.Enabled; DestinationId = $Listed.DestinationId
            Tenants = $Listed.Tenants; Workloads = $Listed.Workloads; Schedules = $Listed.Schedules; Exclusions = $Listed.Exclusions
            RetentionDays = $Listed.RetentionDays; Encryption = $Listed.Encryption
        }
        $Json = $Body | ConvertTo-Json -Depth 10 | ConvertFrom-Json

        (Invoke-ExecCloudBackupPolicy -Request (New-CloudBackupRequest -Endpoint 'ExecCloudBackupPolicy' -Body $Json)).StatusCode | Should -Be 200
        $script:Saved.Tenants | Should -Be '[{"type":"Tenant","customerId":"c1"},{"type":"Group","id":"g1"}]'
        $script:Saved.Workloads | Should -Be '["exchange","onedrive"]'
        $script:Saved.Schedules | Should -Be '{"exchange":"4h","onedrive":"6h"}'
        $script:Saved.NextRuns | Should -Be '{"exchange":"2026-01-01T00:00:00.0000000Z","onedrive":"2026-01-01T00:00:00.0000000Z"}'
        $script:Saved.Exclusions | Should -Be '{"Users":[],"Groups":[],"Sites":[]}'
    }

    It 'shows a restricted caller only policies that target just their tenants' {
        $script:Allowed = @('c1', 'c2')
        $script:PolicyRows = @(
            New-CloudBackupPolicyRow -Tenants '[{"type":"Tenant","customerId":"c1"}]'
            New-CloudBackupPolicyRow -Id '33333333-3333-3333-3333-333333333333' -Tenants '[{"type":"AllTenants"}]'
            New-CloudBackupPolicyRow -Id '44444444-4444-4444-4444-444444444444' -Tenants '[{"type":"Tenant","customerId":"c3"}]'
        )

        @((Invoke-List).Body.Id) | Should -Be @('11111111-1111-1111-1111-111111111111')
    }

    It 'lists only the policies that back up the selected tenant' {
        $script:PolicyRows = @(
            New-CloudBackupPolicyRow -Tenants '[{"type":"Tenant","customerId":"c1"}]'
            New-CloudBackupPolicyRow -Id '33333333-3333-3333-3333-333333333333' -Tenants '[{"type":"AllTenants"}]'
            New-CloudBackupPolicyRow -Id '44444444-4444-4444-4444-444444444444' -Tenants '[{"type":"Tenant","customerId":"c3"}]'
            New-CloudBackupPolicyRow -Id '55555555-5555-5555-5555-555555555555' -Tenants '[{"type":"Group","id":"g1"}]'
        )
        Mock Expand-CIPPTenantGroups { [pscustomobject]@{ addedFields = [pscustomobject]@{ customerId = 'c3' } } }

        @((Invoke-List -Query @{ tenantFilter = 'tailspin.com' }).Body.Id) | Should -Be @('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555')
        @((Invoke-List -Query @{ tenantFilter = 'AllTenants' }).Body).Count | Should -Be 4
        (Invoke-List -Query @{ tenantFilter = 'tailspin.com'; Id = '11111111-1111-1111-1111-111111111111' }).StatusCode | Should -Be 200
        (Invoke-List -Query @{ tenantFilter = 'unknown.com' }).StatusCode | Should -Be 404
    }

    It 'returns 400 for a bad Id and 404 for a policy that is not visible' {
        (Invoke-List -Query @{ Id = 'x' }).StatusCode | Should -Be 400
        $script:Allowed = @('c9')
        $script:PolicyRows = @(New-CloudBackupPolicyRow)
        (Invoke-List -Query @{ Id = '11111111-1111-1111-1111-111111111111' }).StatusCode | Should -Be 404
    }
}
