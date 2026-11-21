BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/CIPPCore/Public/CloudBackup/Get-CIPPCloudBackupOwnerSource.ps1')
    function Get-CIPPCloudBackupRecoveryPoint { param($Destination, $OwnerPrefix) }
    $script:PolicyId = '11111111-1111-1111-1111-111111111111'
    function Invoke-Points {
        param($Query)
        Invoke-ListCloudBackupRecoveryPoints -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupRecoveryPoints' -Query $Query)
    }
}

Describe 'Invoke-ListCloudBackupRecoveryPoints' {
    BeforeEach {
        $script:Allowed = @('AllTenants')
        $script:PolicyRow = New-CloudBackupPolicyRow
        $script:StateRow = [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'onedrive_u_1'; OwnerId = 'u/1'; OwnerType = 'OneDrive' }
        Mock Test-CIPPAccess { $script:Allowed }
        Mock Get-Tenants { $script:CloudBackupTenants }
        Mock Get-CIPPAzDataTableEntity { $script:PolicyRow } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity { $script:StateRow } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Id = $Id; Provider = 'AzureBlob'; Secret = 's' } }
        Mock Get-CIPPCloudBackupRecoveryPoint {
            [pscustomobject]@{ RunStamp = '20261120T040000Z'; At = [datetime]::new(2026, 11, 20, 4, 0, 0, [DateTimeKind]::Utc) }
            [pscustomobject]@{ RunStamp = '20261120T000000Z'; At = [datetime]::new(2026, 11, 20, 0, 0, 0, [DateTimeKind]::Utc) }
        }
        Mock Write-LogMessage { }
    }

    It 'returns the recovery points of the owner, newest first, read from its storage prefix' {
        $Response = Invoke-Points -Query @{ PolicyId = $script:PolicyId; TenantId = 'c1'; Workload = 'onedrive'; OwnerId = 'u/1' }

        $Response.StatusCode | Should -Be 200
        $Rows = @($Response.Body)
        @($Rows.RunStamp) | Should -Be @('20261120T040000Z', '20261120T000000Z')
        $Rows[0].At | Should -Be '2026-11-20T04:00:00.0000000Z'
        Should -Invoke Get-CIPPCloudBackupRecoveryPoint -Times 1 -Exactly -ParameterFilter { $OwnerPrefix -eq "$($script:PolicyId)/c1/onedrive/u_1/" -and $Destination.Secret -eq 's' }
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'CloudBackupState' -and $Filter -eq "PartitionKey eq '$($script:PolicyId)_c1' and RowKey eq 'onedrive_u_1'" -and ($Property -contains 'RowKey') }
    }

    It 'returns 400 when OwnerId is missing' {
        (Invoke-Points -Query @{ PolicyId = $script:PolicyId; TenantId = 'c1'; Workload = 'onedrive' }).StatusCode | Should -Be 400
    }

    It 'returns 404 when <Case>' -ForEach @(
        @{ Case = 'the policy is gone'; Setup = { $script:PolicyRow = $null } }
        @{ Case = 'the destination is gone'; Setup = { Mock Get-CIPPCloudBackupDestination { } } }
        @{ Case = 'the owner was never backed up'; Setup = { $script:StateRow = $null } }
    ) {
        & $Setup
        (Invoke-Points -Query @{ PolicyId = $script:PolicyId; TenantId = 'c1'; Workload = 'onedrive'; OwnerId = 'u/1' }).StatusCode | Should -Be 404
        Should -Invoke Get-CIPPCloudBackupRecoveryPoint -Times 0 -Exactly
    }

    It 'returns 403 to a caller without access to the tenant' {
        $script:Allowed = @('c2')
        (Invoke-Points -Query @{ PolicyId = $script:PolicyId; TenantId = 'c1'; Workload = 'onedrive'; OwnerId = 'u/1' }).StatusCode | Should -Be 403
        Should -Invoke Get-CIPPCloudBackupRecoveryPoint -Times 0 -Exactly
    }

    It 'returns 500 when the storage cannot be read' {
        Mock Get-CIPPCloudBackupRecoveryPoint { throw 'storage down' }
        (Invoke-Points -Query @{ PolicyId = $script:PolicyId; TenantId = 'c1'; Workload = 'onedrive'; OwnerId = 'u/1' }).StatusCode | Should -Be 500
    }
}
