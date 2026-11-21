BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    $script:PolicyId = '11111111-1111-1111-1111-111111111111'
    function New-TenantItem {
        param($Workload = 'exchange')
        [pscustomobject]@{ FunctionName = 'CloudBackupTenant'; PolicyId = $script:PolicyId; customerId = 'c1'; Workload = $Workload; QueueId = 'queue-1'; QueueName = 'contoso.com' }
    }
}

Describe 'Push-CloudBackupTenant' {
    BeforeEach {
        $script:RunWrites = [System.Collections.Generic.List[object]]::new()
        $script:PermissionWrites = [System.Collections.Generic.List[object]]::new()
        $script:Started = [System.Collections.Generic.List[object]]::new()
        $script:PolicyRow = New-CloudBackupPolicyRow
        $script:Permission = [pscustomobject]@{ PartitionKey = $script:PolicyId; RowKey = 'c1'; Status = 'Granted'; CheckedAt = [datetime]::UtcNow.AddDays(-1).ToString('o'); Workloads = '["exchange","onedrive"]' }
        Mock Get-CIPPAzDataTableEntity { $script:PolicyRow } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity { $script:Permission } -ParameterFilter { $TableName -eq 'CloudBackupPermissions' }
        $script:StateRows = @()
        Mock Get-CIPPAzDataTableEntity { $script:StateRows } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Add-CIPPAzDataTableEntity { $script:RunWrites.Add(@{} + $Entity) } -ParameterFilter { $TableName -eq 'CloudBackupRuns' }
        Mock Add-CIPPAzDataTableEntity { $script:PermissionWrites.Add(@{} + $Entity) } -ParameterFilter { $TableName -eq 'CloudBackupPermissions' }
        Mock Get-Tenants { $script:CloudBackupTenants[0] }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Id = '22222222-2222-2222-2222-222222222222'; Name = 'Blob'; Provider = 'AzureBlob' } }
        Mock Get-CIPPCloudBackupOwnerList {
            [pscustomobject]@{ OwnerId = 'u1'; OwnerType = 'UserMailbox'; DisplayName = 'Ann'; UserId = 'u1'; UserPrincipalName = 'ann@contoso.com'; SiteUrl = $null }
            [pscustomobject]@{ OwnerId = 'u2'; OwnerType = 'SharedMailbox'; DisplayName = 'Info'; UserId = 'u2'; UserPrincipalName = 'info@contoso.com'; SiteUrl = $null }
        }
        Mock Grant-CIPPCloudBackupPermission { [pscustomobject]@{ Status = 'Granted'; Message = $null; CheckedAt = '2026-11-20T00:00:00.0000000Z' } }
        Mock Update-CippQueueEntry { }
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject); 'Craft-run' }
        Mock Write-LogMessage { }
    }

    It 'records a run with its owner count and queues one owner task per owner with a finalising post-execution' {
        Push-CloudBackupTenant -Item (New-TenantItem)

        $Run = $script:RunWrites[-1]
        $Run.PartitionKey | Should -Be $script:PolicyId
        $Run.RowKey | Should -Match '^\d{19}_c1_exchange$'
        $Run.RunId | Should -Be "$($script:PolicyId)_$($Run.RowKey)"
        $Run.RunStamp | Should -Match '^\d{8}T\d{6}Z$'
        $Run.Workload | Should -Be 'exchange'
        $Run.Status | Should -Be 'Running'
        $Run.Owners | Should -Be 2
        $Run.Tenant | Should -Be 'contoso.com'
        $Run.PolicyName | Should -Be 'Nightly'
        $Run.Location | Should -Be "$($script:PolicyId)/c1/exchange/"

        $script:Started.Count | Should -Be 1
        $Orchestration = $script:Started[0]
        $Orchestration.OrchestratorName | Should -Be "CloudBackup_$($script:PolicyId)_c1_exchange"
        $Orchestration.AllowCollision | Should -BeFalse
        $Orchestration.PostExecution.FunctionName | Should -Be 'CloudBackupRunFinalise'
        $Orchestration.PostExecution.Parameters.RunId | Should -Be $Run.RunId
        $Batch = @($Orchestration.Batch)
        $Batch.Count | Should -Be 2
        $Batch[0].FunctionName | Should -Be 'CloudBackupOwner'
        $Batch[0].OwnerId | Should -Be 'u1'
        $Batch[1].OwnerType | Should -Be 'SharedMailbox'
        $Batch[0].RunId | Should -Be $Run.RunId
        $Batch[0].RunStamp | Should -Be $Run.RunStamp
        $Batch[0].customerId | Should -Be 'c1'
        $Batch[0].Workload | Should -Be 'exchange'
        Should -Invoke Get-CIPPCloudBackupOwnerList -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.com' -and $Workload -eq 'exchange' -and $null -ne $Exclusions }
        Should -Invoke Update-CippQueueEntry -Times 1 -Exactly -ParameterFilter { $RowKey -eq 'queue-1' -and $TotalTasks -eq 2 -and $IncrementTotalTasks }
        Should -Invoke Grant-CIPPCloudBackupPermission -Times 0 -Exactly
    }

    It 'grants permissions first when the tenant has <Case>' -ForEach @(
        @{ Case = 'no status'; Permission = $null }
        @{ Case = 'a failed grant'; Permission = [pscustomobject]@{ Status = 'Failed'; CheckedAt = [datetime]::UtcNow.ToString('o'); Workloads = '["exchange"]' } }
        @{ Case = 'a pending grant'; Permission = [pscustomobject]@{ Status = 'Pending'; CheckedAt = [datetime]::UtcNow.ToString('o'); Workloads = '["exchange"]' } }
        @{ Case = 'a grant older than 7 days'; Permission = [pscustomobject]@{ Status = 'Granted'; CheckedAt = [datetime]::UtcNow.AddDays(-8).ToString('o'); Workloads = '["exchange"]' } }
        @{ Case = 'a grant without this workload'; Permission = [pscustomobject]@{ Status = 'Granted'; CheckedAt = [datetime]::UtcNow.ToString('o'); Workloads = '["onedrive"]' } }
    ) {
        $script:Permission = $Permission

        Push-CloudBackupTenant -Item (New-TenantItem)

        Should -Invoke Grant-CIPPCloudBackupPermission -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'c1' -and (@($Workloads) -join ',') -eq 'exchange,onedrive' }
        $script:PermissionWrites[0].PartitionKey | Should -Be $script:PolicyId
        $script:PermissionWrites[0].RowKey | Should -Be 'c1'
        $script:PermissionWrites[0].Status | Should -Be 'Granted'
        $script:PermissionWrites[0].Workloads | Should -Be '["exchange","onedrive"]'
        $script:Started.Count | Should -Be 1
    }

    It 'still backs up and warns on the run when the grant fails' {
        $script:Permission = $null
        Mock Grant-CIPPCloudBackupPermission { [pscustomobject]@{ Status = 'Failed'; Message = 'Insufficient privileges'; CheckedAt = '2026-11-20T00:00:00.0000000Z' } }

        Push-CloudBackupTenant -Item (New-TenantItem)

        $script:PermissionWrites[0].Status | Should -Be 'Failed'
        $script:PermissionWrites[0].Message | Should -Be 'Insufficient privileges'
        $script:RunWrites[-1].Warnings | Should -Be '["Permissions: Insufficient privileges"]'
        $script:Started.Count | Should -Be 1
    }

    It 'completes the run straight away when there are no owners' {
        Mock Get-CIPPCloudBackupOwnerList { }

        Push-CloudBackupTenant -Item (New-TenantItem)

        $script:RunWrites[-1].Status | Should -Be 'Succeeded'
        $script:RunWrites[-1].Owners | Should -Be 0
        $script:RunWrites[-1].CompletedAt | Should -Not -BeNullOrEmpty
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }

    It 'marks the run Skipped when the previous run of the tenant and workload is still going' {
        Mock Start-CIPPOrchestrator { 'Craft-CloudBackup_x-queue-1-Skipped' }

        Push-CloudBackupTenant -Item (New-TenantItem)

        $script:RunWrites[-1].Status | Should -Be 'Skipped'
        $script:RunWrites[-1].Warnings | Should -BeLike '*still running*'
    }

    It 'records a failed run without throwing when <Case>' -ForEach @(
        @{ Case = 'the policy is gone'; Setup = { $script:PolicyRow = $null } }
        @{ Case = 'the policy no longer backs up the workload'; Setup = { $script:Workload = 'teams' } }
        @{ Case = 'the tenant is gone'; Setup = { Mock Get-Tenants { } } }
        @{ Case = 'the destination is gone'; Setup = { Mock Get-CIPPCloudBackupDestination { } } }
        @{ Case = 'the owners cannot be listed'; Setup = { Mock Get-CIPPCloudBackupOwnerList { throw 'Graph said no' } } }
        @{ Case = 'the owner tasks cannot be queued'; Setup = { Mock Start-CIPPOrchestrator { throw 'queue down' } } }
    ) {
        $script:Workload = 'exchange'
        & $Setup

        { Push-CloudBackupTenant -Item (New-TenantItem -Workload $script:Workload) } | Should -Not -Throw

        $script:RunWrites[-1].Status | Should -Be 'Failed'
        $script:RunWrites[-1].CompletedAt | Should -Not -BeNullOrEmpty
        $script:RunWrites[-1].Warnings | Should -Not -Be '[]'
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Error' }
    }
}

Describe 'Push-CloudBackupTenant removed owners' {
    BeforeEach {
        $script:RunWrites = [System.Collections.Generic.List[object]]::new()
        $script:Started = [System.Collections.Generic.List[object]]::new()
        $script:PolicyRow = New-CloudBackupPolicyRow
        $script:StateRows = @(
            [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_u1'; OwnerId = 'u1'; OwnerType = 'UserMailbox'; DisplayName = 'Ann'; Removed = $false }
            [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_gone'; OwnerId = 'gone'; OwnerType = 'UserMailbox'; DisplayName = 'Gone'; Removed = $false }
            [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_old'; OwnerId = 'old'; OwnerType = 'UserMailbox'; DisplayName = 'Old'; Removed = $true }
            [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_sales_x'; OwnerId = 'sales/x'; OwnerType = 'SharedMailbox'; DisplayName = 'Sales' }
        )
        Mock Get-CIPPAzDataTableEntity { $script:PolicyRow } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ Status = 'Granted'; CheckedAt = [datetime]::UtcNow.ToString('o'); Workloads = '["exchange","onedrive"]' } } -ParameterFilter { $TableName -eq 'CloudBackupPermissions' }
        Mock Get-CIPPAzDataTableEntity { $script:StateRows } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Add-CIPPAzDataTableEntity { $script:RunWrites.Add(@{} + $Entity) } -ParameterFilter { $TableName -eq 'CloudBackupRuns' }
        Mock Get-Tenants { $script:CloudBackupTenants[0] }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Id = '22222222-2222-2222-2222-222222222222'; Provider = 'AzureBlob' } }
        Mock Get-CIPPCloudBackupOwnerList {
            [pscustomobject]@{ OwnerId = 'u1'; OwnerType = 'UserMailbox'; DisplayName = 'Ann' }
            [pscustomobject]@{ OwnerId = 'sales/x'; OwnerType = 'SharedMailbox'; DisplayName = 'Sales' }
        }
        Mock Get-CIPPCloudBackupExchangeOwner { }
        Mock Update-CippQueueEntry { }
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject); 'Craft-run' }
        Mock Write-LogMessage { }
    }

    It 'queues owners that are backed up but no longer listed, once, and still backs up the others' {
        Push-CloudBackupTenant -Item ([pscustomobject]@{ PolicyId = $script:PolicyId; customerId = 'c1'; Workload = 'exchange'; QueueId = 'queue-1' })

        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $TableName -eq 'CloudBackupState' -and $Filter -eq "PartitionKey eq '$($script:PolicyId)_c1' and RowKey ge 'exchange_' and RowKey lt 'exchange``'" -and
            ($Property -contains 'PartitionKey') -and ($Property -contains 'RowKey') -and ($Property -contains 'Removed') -and ($Property -notcontains 'State')
        }
        $Removed = @($script:Started.Where({ $_.OrchestratorName -like 'CloudBackupRemoved_*' }))
        $Removed.Count | Should -Be 1
        $Removed[0].OrchestratorName | Should -Be "CloudBackupRemoved_$($script:PolicyId)_c1_exchange"
        $Batch = @($Removed[0].Batch)
        $Batch.Count | Should -Be 1
        $Batch[0].FunctionName | Should -Be 'CloudBackupOwnerRemoved'
        $Batch[0].OwnerId | Should -Be 'gone'
        $Batch[0].DisplayName | Should -Be 'Gone'
        $Batch[0].Reason | Should -Be 'Removed'
        $Batch[0].customerId | Should -Be 'c1'
        $Batch[0].Workload | Should -Be 'exchange'
        Should -Invoke Get-CIPPCloudBackupExchangeOwner -Times 0 -Exactly
        @($script:Started.Where({ $_.OrchestratorName -eq "CloudBackup_$($script:PolicyId)_c1_exchange" })[0].Batch).Count | Should -Be 2
        $script:RunWrites[-1].Warnings | Should -Be '[]'
    }

    It 'labels an owner that is still in the tenant but excluded by the policy as Excluded' {
        $script:PolicyRow = New-CloudBackupPolicyRow -Exclusions '{"Users":["gone"],"Groups":[],"Sites":[]}'
        Mock Get-CIPPCloudBackupExchangeOwner { [pscustomobject]@{ OwnerId = 'gone' }; [pscustomobject]@{ OwnerId = 'u1' } }

        Push-CloudBackupTenant -Item ([pscustomobject]@{ PolicyId = $script:PolicyId; customerId = 'c1'; Workload = 'exchange' })

        Should -Invoke Get-CIPPCloudBackupExchangeOwner -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.com' }
        @($script:Started.Where({ $_.OrchestratorName -like 'CloudBackupRemoved_*' })[0].Batch)[0].Reason | Should -Be 'Excluded'
    }

    It 'queues nothing when every backed-up owner is still listed or already removed' {
        $script:StateRows = @($script:StateRows[0], $script:StateRows[2])
        Push-CloudBackupTenant -Item ([pscustomobject]@{ PolicyId = $script:PolicyId; customerId = 'c1'; Workload = 'exchange' })
        @($script:Started.Where({ $_.OrchestratorName -like 'CloudBackupRemoved_*' })).Count | Should -Be 0
    }

    It 'does not treat every owner as removed when the owner list comes back empty' {
        Mock Get-CIPPCloudBackupOwnerList { }
        Push-CloudBackupTenant -Item ([pscustomobject]@{ PolicyId = $script:PolicyId; customerId = 'c1'; Workload = 'exchange' })
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $TableName -eq 'CloudBackupState' }
    }

    It 'warns on the run but still backs up when removed owners cannot be checked' {
        Mock Get-CIPPAzDataTableEntity { throw 'table down' } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Push-CloudBackupTenant -Item ([pscustomobject]@{ PolicyId = $script:PolicyId; customerId = 'c1'; Workload = 'exchange' })
        $script:RunWrites[-1].Warnings | Should -BeLike '*removed owners*table down*'
        @($script:Started.Where({ $_.OrchestratorName -eq "CloudBackup_$($script:PolicyId)_c1_exchange" })).Count | Should -Be 1
    }
}

Describe 'Push-CloudBackupRunFinalise' {
    BeforeEach {
        $script:RunId = "$($script:PolicyId)_0000000000000000001_c1_exchange"
        $script:RunRow = [pscustomobject]@{ PartitionKey = $script:PolicyId; RowKey = '0000000000000000001_c1_exchange'; Owners = 3; Warnings = '[]'; Tenant = 'contoso.com'; TenantId = 'c1'; PolicyName = 'Nightly'; Workload = 'exchange' }
        $script:OwnerRows = @(
            [pscustomobject]@{ PartitionKey = $script:RunId; RowKey = 'u1'; Status = 'Succeeded'; Items = 10; Bytes = 1000; Deleted = 1 }
            [pscustomobject]@{ PartitionKey = $script:RunId; RowKey = 'u2'; Status = 'PartialSuccess'; Items = 5; Bytes = 500; Deleted = 0 }
            [pscustomobject]@{ PartitionKey = $script:RunId; RowKey = 'u3'; Status = 'Succeeded'; Items = 1; Bytes = 10; Deleted = 2 }
        )
        $script:Update = $null
        Mock Get-CIPPAzDataTableEntity { $script:RunRow } -ParameterFilter { $TableName -eq 'CloudBackupRuns' }
        Mock Get-CIPPAzDataTableEntity { $script:OwnerRows } -ParameterFilter { $TableName -eq 'CloudBackupRunOwners' }
        Mock Add-CIPPAzDataTableEntity { $script:Update = [pscustomobject]@{ Entity = $Entity; OperationType = $OperationType } } -ParameterFilter { $TableName -eq 'CloudBackupRuns' }
        Mock Write-LogMessage { }
    }

    It 'sums the owner results into the run row' {
        Push-CloudBackupRunFinalise -Item @{ Parameters = @{ RunId = $script:RunId } }

        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'CloudBackupRunOwners' -and $Filter -eq "PartitionKey eq '$($script:RunId)'" -and ($Property -contains 'RowKey') -and ($Property -contains 'PartitionKey') }
        $script:Update.OperationType | Should -Be 'UpsertMerge'
        $Entity = $script:Update.Entity
        $Entity.PartitionKey | Should -Be $script:PolicyId
        $Entity.RowKey | Should -Be '0000000000000000001_c1_exchange'
        $Entity.Items | Should -Be 16
        $Entity.Bytes | Should -Be 1510
        $Entity.Deleted | Should -Be 3
        $Entity.OwnersSucceeded | Should -Be 3
        $Entity.OwnersFailed | Should -Be 0
        $Entity.Status | Should -Be 'PartialSuccess'
        $Entity.CompletedAt | Should -Not -BeNullOrEmpty
    }

    It 'returns <Expected> for <Case>' -ForEach @(
        @{ Case = 'all owners succeeded'; Statuses = @('Succeeded', 'Succeeded', 'Succeeded'); Expected = 'Succeeded'; Failed = 0 }
        @{ Case = 'all owners failed'; Statuses = @('Failed', 'Failed', 'Failed'); Expected = 'Failed'; Failed = 3 }
        @{ Case = 'an owner that never finished'; Statuses = @('Succeeded', 'Succeeded', 'Running'); Expected = 'PartialSuccess'; Failed = 1 }
        @{ Case = 'an owner that never recorded anything'; Statuses = @('Succeeded', 'Succeeded'); Expected = 'PartialSuccess'; Failed = 1 }
    ) {
        $script:OwnerRows = @(for ($i = 0; $i -lt $Statuses.Count; $i++) { [pscustomobject]@{ PartitionKey = $script:RunId; RowKey = "u$i"; Status = $Statuses[$i]; Items = 1; Bytes = 1; Deleted = 0 } })

        Push-CloudBackupRunFinalise -Item @{ Parameters = @{ RunId = $script:RunId } }

        $script:Update.Entity.Status | Should -Be $Expected
        $script:Update.Entity.OwnersFailed | Should -Be $Failed
    }

    It 'keeps the run warnings and adds the failed count' {
        $script:RunRow.Warnings = '["Permissions: denied"]'
        $script:OwnerRows = @([pscustomobject]@{ PartitionKey = $script:RunId; RowKey = 'u1'; Status = 'Failed'; Items = 0; Bytes = 0; Deleted = 0 })

        Push-CloudBackupRunFinalise -Item @{ Parameters = @{ RunId = $script:RunId } }

        @($script:Update.Entity.Warnings | ConvertFrom-Json) | Should -Be @('Permissions: denied', '3 of 3 items failed or did not finish')
    }

    It 'ignores a bad or unknown run id without throwing' {
        { Push-CloudBackupRunFinalise -Item @{ Parameters = @{ RunId = "x' or 1 eq 1" } } } | Should -Not -Throw
        $script:RunRow = $null
        { Push-CloudBackupRunFinalise -Item @{ Parameters = @{ RunId = $script:RunId } } } | Should -Not -Throw
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }
}

Describe 'Push-CloudBackupGrant' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:PolicyRow = New-CloudBackupPolicyRow -Workloads '["teams","sharepoint"]'
        Mock Get-CIPPAzDataTableEntity { $script:PolicyRow } -ParameterFilter { $TableName -eq 'Config' }
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add(@{} + $Entity) } -ParameterFilter { $TableName -eq 'CloudBackupPermissions' }
        Mock Grant-CIPPCloudBackupPermission { [pscustomobject]@{ Status = 'Failed'; Message = 'GDAP role missing'; CheckedAt = '2026-11-20T00:00:00.0000000Z' } }
        Mock Write-LogMessage { }
    }

    It 'grants the policy workloads in the tenant and records the status' {
        Push-CloudBackupGrant -Item ([pscustomobject]@{ PolicyId = $script:PolicyId; customerId = 'c2'; QueueName = 'fabrikam.com' })

        Should -Invoke Grant-CIPPCloudBackupPermission -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'c2' -and (@($Workloads) -join ',') -eq 'teams,sharepoint' }
        $script:Writes[0].PartitionKey | Should -Be $script:PolicyId
        $script:Writes[0].RowKey | Should -Be 'c2'
        $script:Writes[0].Status | Should -Be 'Failed'
        $script:Writes[0].Message | Should -Be 'GDAP role missing'
        $script:Writes[0].Workloads | Should -Be '["teams","sharepoint"]'
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' }
    }

    It 'does nothing for a deleted policy' {
        $script:PolicyRow = $null
        Push-CloudBackupGrant -Item ([pscustomobject]@{ PolicyId = $script:PolicyId; customerId = 'c2' })
        Should -Invoke Grant-CIPPCloudBackupPermission -Times 0 -Exactly
        $script:Writes.Count | Should -Be 0
    }
}

Describe 'Push-CloudBackupPrune' {
    BeforeEach {
        $script:Update = $null
        $script:PolicyRow = New-CloudBackupPolicyRow -RetentionDays 45
        Mock Get-CIPPAzDataTableEntity { $script:PolicyRow } -ParameterFilter { $TableName -eq 'Config' }
        Mock Add-CIPPAzDataTableEntity { $script:Update = [pscustomobject]@{ Entity = $Entity; OperationType = $OperationType } } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Id = $Id; Name = 'Blob'; Provider = 'AzureBlob'; Secret = 's' } }
        Mock Remove-CIPPCloudBackupExpiredVersion { [pscustomobject]@{ Examined = 100; Deleted = 40; Failed = 0; Errors = @() } }
        Mock Write-LogMessage { }
    }

    It 'removes versions older than the retention under the policy prefix and records <Expected>' -ForEach @(
        @{ Deleted = 40; Expected = 'Succeeded' }
        @{ Deleted = 5000; Expected = 'Partial' }
    ) {
        Mock Remove-CIPPCloudBackupExpiredVersion { [pscustomobject]@{ Examined = 9000; Deleted = $Deleted; Failed = 0; Errors = @() } }

        Push-CloudBackupPrune -Item ([pscustomobject]@{ PolicyId = $script:PolicyId })

        Should -Invoke Remove-CIPPCloudBackupExpiredVersion -Times 1 -Exactly -ParameterFilter { $Prefix -eq "$($script:PolicyId)/" -and $Days -eq 45 -and $MaxDeletes -eq 5000 -and $Destination.Secret -eq 's' }
        Should -Invoke Get-CIPPCloudBackupDestination -ParameterFilter { $IncludeSecret }
        $script:Update.OperationType | Should -Be 'UpsertMerge'
        $script:Update.Entity.RowKey | Should -Be $script:PolicyId
        $script:Update.Entity.PruneStatus | Should -Be $Expected
        $script:Update.Entity.PruneError | Should -Be ''
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }

    It 'records Failed and warns when <Case>' -ForEach @(
        @{ Case = 'versions could not be removed'; Setup = { Mock Remove-CIPPCloudBackupExpiredVersion { [pscustomobject]@{ Examined = 3; Deleted = 1; Failed = 2; Errors = @('403 AuthorizationPermissionMismatch', 'x') } } }; Like = '*2 old versions*AuthorizationPermissionMismatch*' }
        @{ Case = 'listing versions throws'; Setup = { Mock Remove-CIPPCloudBackupExpiredVersion { throw 'Storage Blob Data Owner is required' } }; Like = '*Storage Blob Data Owner*' }
        @{ Case = 'the destination is gone'; Setup = { Mock Get-CIPPCloudBackupDestination { } }; Like = '*no longer exists*' }
    ) {
        & $Setup

        { Push-CloudBackupPrune -Item ([pscustomobject]@{ PolicyId = $script:PolicyId }) } | Should -Not -Throw

        $script:Update.Entity.PruneStatus | Should -Be 'Failed'
        $script:Update.Entity.PruneError | Should -BeLike $Like
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' }
    }

    It 'does nothing for a deleted policy' {
        $script:PolicyRow = $null
        Push-CloudBackupPrune -Item ([pscustomobject]@{ PolicyId = $script:PolicyId })
        Should -Invoke Remove-CIPPCloudBackupExpiredVersion -Times 0 -Exactly
        $script:Update | Should -BeNullOrEmpty
    }
}
