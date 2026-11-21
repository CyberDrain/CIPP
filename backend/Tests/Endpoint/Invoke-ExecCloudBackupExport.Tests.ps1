BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/CIPPCore/Public/CloudBackup/Resolve-CIPPCloudBackupJobSource.ps1')
    function Get-CIPPCloudBackupRecoveryPoint { param($Destination, $OwnerPrefix) }

    $script:PolicyId = '11111111-1111-1111-1111-111111111111'
    function Invoke-Export {
        param([hashtable]$Body)
        Invoke-ExecCloudBackupExport -Request (New-CloudBackupRequest -Endpoint 'ExecCloudBackupExport' -Body $Body)
    }
    function New-Body {
        param([hashtable]$Extra = @{})
        $Body = @{ PolicyId = $script:PolicyId; TenantId = 'c1'; Workload = 'teams'; OwnerId = 'team-1'; Paths = @('General') }
        foreach ($Name in $Extra.PSBase.Keys) { $Body[$Name] = $Extra[$Name] }
        $Body
    }
}

Describe 'Invoke-ExecCloudBackupExport' {
    BeforeEach {
        $script:Allowed = @('AllTenants')
        $script:StateRow = [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'teams_team-1'; OwnerId = 'team-1'; OwnerType = 'Team'; LastRunId = ''; Removed = $true; RemovedReason = 'Removed' }
        $script:JobWrites = [System.Collections.Generic.List[object]]::new()
        $script:Queued = 'run-1'
        Mock Test-CIPPAccess { $script:Allowed }
        Mock Get-Tenants { $script:CloudBackupTenants }
        Mock Get-CIPPCloudBackupPolicy { [pscustomobject]@{ Id = $script:PolicyId; Name = 'Nightly'; DestinationId = '22222222-2222-2222-2222-222222222222'; Encryption = $false; CurrentKeyId = '' } }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Provider = 'S3' } }
        Mock Get-CIPPCloudBackupRecoveryPoint { [pscustomobject]@{ RunStamp = '20261101T000000Z'; At = [datetime]::new(2026, 11, 1, 0, 0, 0, [System.DateTimeKind]::Utc) } }
        Mock Get-CIPPAzDataTableEntity { $script:StateRow } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Add-CIPPAzDataTableEntity { $script:JobWrites.Add($Entity) } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Start-CIPPOrchestrator { $script:Queued }
        Mock Write-LogMessage { }
    }

    It 'returns 400 for <Name>' -ForEach @(
        @{ Name = 'a bad policy id'; Extra = @{ PolicyId = '' } }
        @{ Name = 'a tenant group'; Extra = @{ TenantId = 'group:1' } }
        @{ Name = 'an unknown workload'; Extra = @{ Workload = 'intune' } }
        @{ Name = 'a missing owner'; Extra = @{ OwnerId = $null } }
        @{ Name = 'a bad AsOf'; Extra = @{ AsOf = 'soon' } }
    ) {
        (Invoke-Export -Body (New-Body -Extra $Extra)).StatusCode | Should -Be 400
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }

    It 'returns 403 for a tenant the caller cannot access and 404 for an owner without a backup' {
        $script:Allowed = @('c2')
        (Invoke-Export -Body (New-Body)).StatusCode | Should -Be 403
        $script:Allowed = @('AllTenants')
        $script:StateRow = $null
        (Invoke-Export -Body (New-Body)).StatusCode | Should -Be 404
    }

    It 'queues an export of a removed Teams owner' {
        $Response = Invoke-Export -Body (New-Body)

        $Response.StatusCode | Should -Be 202
        $Job = $script:JobWrites[0]
        $Job.Type | Should -Be 'Export'
        $Job.RowKey | Should -Be $Response.Body.JobId
        $Job.Workload | Should -Be 'teams'
        $Job.RunStamp | Should -Be '20261101T000000Z'
        $Job.SourceRemoved | Should -BeTrue
        $Job.DataKeyId | Should -Be ''
        $Job.ManifestReady | Should -BeFalse
        @([CIPP.CippJson]::ConvertFromJson($Job.Parameters).Paths) | Should -Be @('General')
        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly -ParameterFilter { $InputObject.Batch[0].FunctionName -eq 'CloudBackupExport' }
        Should -Invoke Write-LogMessage -ParameterFilter { $API -eq 'CloudBackupRestore' -and $message -like 'Exporting*' }
    }

    It 'returns 500 when the export cannot be queued' {
        $script:Queued = $null
        $Response = Invoke-Export -Body (New-Body)
        $Response.StatusCode | Should -Be 500
        $script:JobWrites[1].Status | Should -Be 'Failed'
    }
}
