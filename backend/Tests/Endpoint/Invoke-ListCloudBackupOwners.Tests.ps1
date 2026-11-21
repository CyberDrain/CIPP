BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    $script:PolicyId = '11111111-1111-1111-1111-111111111111'
    function Invoke-Owners {
        param($Query)
        Invoke-ListCloudBackupOwners -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupOwners' -Query $Query)
    }
}

Describe 'Invoke-ListCloudBackupOwners' {
    BeforeEach {
        $script:Allowed = @('AllTenants')
        $script:PolicyRow = New-CloudBackupPolicyRow
        $script:StateRows = @(
            [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_u2'; OwnerId = 'u2'; OwnerType = 'UserMailbox'; DisplayName = 'Zed'; UserPrincipalName = 'zed@contoso.com'; SiteUrl = ''; Removed = $false; RemovedAt = ''; RemovedReason = ''; LastSuccessAt = '2026-11-19T00:00:00.0000000Z'; Items = 10; Bytes = 2048; Status = 'Idle'; LastError = '' }
            [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_u1'; OwnerId = 'u1'; OwnerType = 'UserMailbox'; DisplayName = 'Ann'; UserPrincipalName = 'ann@contoso.com'; Removed = $true; RemovedAt = '2026-11-18T00:00:00.0000000Z'; RemovedReason = 'Excluded'; LastSuccessAt = '2026-11-01T00:00:00.0000000Z'; Items = 5; Bytes = 100; Status = 'Idle' }
            [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_u3'; OwnerId = 'u3'; OwnerType = 'SharedMailbox'; Removed = $true; RemovedAt = '2026-11-17T00:00:00.0000000Z'; Status = 'Idle' }
        )
        Mock Test-CIPPAccess { $script:Allowed }
        Mock Get-Tenants { $script:CloudBackupTenants }
        Mock Get-CIPPAzDataTableEntity { $script:PolicyRow } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity { $script:StateRows } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Write-LogMessage { }
    }

    It 'lists the owners of one workload from the state rows, removed owners included' {
        $Response = Invoke-Owners -Query @{ PolicyId = $script:PolicyId; TenantId = 'contoso.com'; Workload = 'Exchange' }

        $Response.StatusCode | Should -Be 200
        $Rows = @($Response.Body)
        @($Rows.OwnerId) | Should -Be @('u2', 'u1', 'u3')
        $Rows[0].Removed | Should -BeFalse
        $Rows[0].RemovedReason | Should -BeNullOrEmpty
        $Rows[0].UserPrincipalName | Should -Be 'zed@contoso.com'
        $Rows[0].SiteUrl | Should -BeNullOrEmpty
        $Rows[0].Items | Should -Be 10
        $Rows[0].Bytes | Should -Be 2048
        $Rows[0].LastSuccessAt | Should -Be '2026-11-19T00:00:00.0000000Z'
        $Rows[1].Removed | Should -BeTrue
        $Rows[1].RemovedReason | Should -Be 'Excluded'
        $Rows[1].RemovedAt | Should -Be '2026-11-18T00:00:00.0000000Z'
        $Rows[2].RemovedReason | Should -Be 'Removed'
        $Rows[2].DisplayName | Should -Be 'u3'
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $TableName -eq 'CloudBackupState' -and
            $Filter -eq "PartitionKey eq '$($script:PolicyId)_c1' and RowKey ge 'exchange_' and RowKey lt 'exchange``'" -and
            ($Property -contains 'PartitionKey') -and ($Property -contains 'RowKey') -and ($Property -notcontains 'State')
        }
    }

    It 'returns 400 when <Case>' -ForEach @(
        @{ Case = 'PolicyId is not a GUID'; Query = @{ PolicyId = 'x'; TenantId = 'c1'; Workload = 'exchange' } }
        @{ Case = 'TenantId is missing'; Query = @{ PolicyId = '11111111-1111-1111-1111-111111111111'; Workload = 'exchange' } }
        @{ Case = 'the workload is unknown'; Query = @{ PolicyId = '11111111-1111-1111-1111-111111111111'; TenantId = 'c1'; Workload = 'intune' } }
    ) {
        (Invoke-Owners -Query $Query).StatusCode | Should -Be 400
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'returns 404 for an unknown tenant or policy' {
        (Invoke-Owners -Query @{ PolicyId = $script:PolicyId; TenantId = "x' or 1 eq 1"; Workload = 'exchange' }).StatusCode | Should -Be 404
        $script:PolicyRow = $null
        (Invoke-Owners -Query @{ PolicyId = $script:PolicyId; TenantId = 'c1'; Workload = 'exchange' }).StatusCode | Should -Be 404
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $TableName -eq 'CloudBackupState' }
    }

    It 'returns 403 to a caller without access to the tenant' {
        $script:Allowed = @('c2')
        (Invoke-Owners -Query @{ PolicyId = $script:PolicyId; TenantId = 'c1'; Workload = 'exchange' }).StatusCode | Should -Be 403
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $TableName -eq 'CloudBackupState' }
    }

    It 'returns 500 when the state table cannot be read' {
        Mock Get-CIPPAzDataTableEntity { throw 'table down' } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        (Invoke-Owners -Query @{ PolicyId = $script:PolicyId; TenantId = 'c1'; Workload = 'exchange' }).StatusCode | Should -Be 500
    }
}
