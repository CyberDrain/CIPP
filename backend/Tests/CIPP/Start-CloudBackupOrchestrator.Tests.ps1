BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    $script:PolicyId = '11111111-1111-1111-1111-111111111111'
    function Get-NextRuns {
        param($Json)
        $Result = @{}
        foreach ($Match in [regex]::Matches($Json, '"(\w+)":"([^"]+)"')) { $Result[$Match.Groups[1].Value] = $Match.Groups[2].Value }
        $Result
    }
}

Describe 'Start-CloudBackupOrchestrator' {
    BeforeEach {
        $script:Policies = @()
        $script:Started = [System.Collections.Generic.List[object]]::new()
        $script:ConfigWrites = [System.Collections.Generic.List[object]]::new()
        $script:RunWrites = [System.Collections.Generic.List[object]]::new()
        $script:Removed = [System.Collections.Generic.List[object]]::new()
        $script:OldRuns = @()
        $script:StaleRuns = @()
        $script:OwnerRows = @()
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -match "RowKey eq '([^']+)'") { $Key = $Matches[1]; @($script:Policies).Where({ $_.RowKey -eq $Key }) } else { $script:Policies }
        } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity { if ($Filter -like "*Status eq 'Running'*") { $script:StaleRuns } else { $script:OldRuns } } -ParameterFilter { $TableName -eq 'CloudBackupRuns' }
        Mock Get-CIPPAzDataTableEntity { $script:OwnerRows } -ParameterFilter { $TableName -eq 'CloudBackupRunOwners' }
        $script:StateRows = @()
        $script:StateWrites = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPAzDataTableEntity { $script:StateRows } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Add-CIPPAzDataTableEntity { foreach ($Row in @($Entity)) { $script:StateWrites.Add($Row) } } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Add-CIPPAzDataTableEntity { $script:ConfigWrites.Add($Entity) } -ParameterFilter { $TableName -eq 'Config' }
        Mock Add-CIPPAzDataTableEntity { foreach ($Row in @($Entity)) { $script:RunWrites.Add($Row) } } -ParameterFilter { $TableName -eq 'CloudBackupRuns' }
        Mock Remove-CIPPAzDataTableEntity { $script:Removed.Add([pscustomobject]@{ Table = $TableName; Entity = $Entity }) } -ParameterFilter { $TableName -in @('CloudBackupRuns', 'CloudBackupRunOwners') }
        $script:OldJobs = @()
        $script:RemovedJobs = $null
        $script:StuckJobs = @()
        $script:JobWrites = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPAzDataTableEntity { if ($Filter -like '*ExpiresAt*') { @() } elseif ($Filter -like '*Status eq*') { $script:StuckJobs } else { $script:OldJobs } } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Add-CIPPAzDataTableEntity { $script:JobWrites.Add($Entity) } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Remove-CIPPAzDataTableEntity { $script:RemovedJobs = $Entity } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Get-Tenants { $script:CloudBackupTenants }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ RowKey = '22222222-2222-2222-2222-222222222222'; Name = 'Blob'; Provider = 'AzureBlob' } }
        Mock Get-CIPPCloudBackupRetentionRule { @{ Prefix = "$($script:PolicyId)/"; Days = 90; Mode = 'Versioned' } }
        Mock Set-CIPPCloudBackupRetentionRule { }
        Mock New-CippQueueEntry { [pscustomobject]@{ RowKey = 'queue-1' } }
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject); 'run-1' }
        $script:PruneStarted = [System.Collections.Generic.List[object]]::new()
        Mock Start-CIPPOrchestrator { $script:PruneStarted.Add($InputObject) } -ParameterFilter { $InputObject.OrchestratorName -eq 'CloudBackupPrune' }
        Mock Write-LogMessage { }
    }

    It 'queues one task per tenant and due workload of enabled policies only' {
        $Later = [datetime]::UtcNow.AddHours(2).ToString('o')
        $script:Policies = @(
            New-CloudBackupPolicyRow -Name 'Due' -Workloads '["exchange","onedrive","teams"]' -NextRuns ('{"exchange":"2026-01-01T00:00:00Z","onedrive":"' + $Later + '"}')
            New-CloudBackupPolicyRow -Id '33333333-3333-3333-3333-333333333333' -Name 'Later' -NextRuns ('{"exchange":"' + $Later + '","onedrive":"' + $Later + '"}')
            New-CloudBackupPolicyRow -Id '44444444-4444-4444-4444-444444444444' -Name 'Off' -Enabled $false
        )

        Start-CloudBackupOrchestrator | Should -Be 'run-1'

        $script:Started.Count | Should -Be 1
        $script:Started[0].OrchestratorName | Should -Be "CloudBackupPlan_$($script:PolicyId)"
        $Batch = @($script:Started[0].Batch)
        @($Batch.Workload | Sort-Object) | Should -Be @('exchange', 'teams')
        foreach ($Item in $Batch) {
            $Item.FunctionName | Should -Be 'CloudBackupTenant'
            $Item.PolicyId | Should -Be $script:PolicyId
            $Item.customerId | Should -Be 'c1'
            $Item.QueueId | Should -Be 'queue-1'
            $Item.QueueName | Should -Be 'contoso.com'
        }
        Should -Invoke New-CippQueueEntry -Times 1 -Exactly -ParameterFilter { $TotalTasks -eq 2 }
    }

    It 'advances NextRuns of the due workloads by their schedules before queueing and keeps the others' {
        $Later = [datetime]::UtcNow.AddHours(2).ToString('o')
        $script:Policies = @((New-CloudBackupPolicyRow -Workloads '["exchange","onedrive","sharepoint"]' -Schedules '{"exchange":"12h"}' -NextRuns ('{"exchange":"2026-01-01T00:00:00Z","onedrive":"' + $Later + '"}')) | Add-Member -NotePropertyName LastPrunedAt -NotePropertyValue ([datetime]::UtcNow.ToString('o')) -PassThru)
        $script:Order = [System.Collections.Generic.List[string]]::new()
        Mock Add-CIPPAzDataTableEntity { $script:ConfigWrites.Add($Entity); $script:Order.Add('advance') } -ParameterFilter { $TableName -eq 'Config' }
        Mock Start-CIPPOrchestrator { $script:Order.Add('start'); 'run-1' }
        $Before = [datetime]::UtcNow

        Start-CloudBackupOrchestrator | Out-Null

        @($script:Order) | Should -Be @('advance', 'start')
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'Config' -and $OperationType -eq 'UpsertMerge' -and $null -ne $Entity.NextRuns }
        $Update = @($script:ConfigWrites.Where({ $null -ne $_.NextRuns }))[0]
        $Update.RowKey | Should -Be $script:PolicyId
        $Update.PSObject.Properties['ConfigNextRun'] | Should -BeNullOrEmpty
        $NextRuns = Get-NextRuns $Update.NextRuns
        $NextRuns.onedrive | Should -Be ([datetimeoffset]::Parse($Later).UtcDateTime.ToString('o'))
        $Exchange = [datetimeoffset]::Parse($NextRuns.exchange).UtcDateTime
        $Exchange | Should -BeGreaterOrEqual $Before.AddHours(12).AddSeconds(-1)
        $Exchange | Should -BeLessOrEqual ([datetime]::UtcNow.AddHours(12).AddSeconds(1))
        $SharePoint = [datetimeoffset]::Parse($NextRuns.sharepoint).UtcDateTime
        $SharePoint | Should -BeGreaterOrEqual $Before.AddHours(6).AddSeconds(-1)
        $SharePoint | Should -BeLessOrEqual ([datetime]::UtcNow.AddHours(6).AddSeconds(1))
    }

    It 'uses the default schedule of each workload: <Workload> every <Hours> hours' -ForEach @(
        @{ Workload = 'exchange'; Hours = 4 }, @{ Workload = 'teams'; Hours = 4 }, @{ Workload = 'onedrive'; Hours = 6 }, @{ Workload = 'sharepoint'; Hours = 6 }
    ) {
        $script:Policies = @(New-CloudBackupPolicyRow -Workloads "[`"$Workload`"]" -Schedules '{}' -NextRuns '{}')
        $Before = [datetime]::UtcNow

        Start-CloudBackupOrchestrator | Out-Null

        $Next = [datetimeoffset]::Parse((Get-NextRuns @($script:ConfigWrites.Where({ $null -ne $_.NextRuns }))[0].NextRuns)[$Workload]).UtcDateTime
        $Next | Should -BeGreaterOrEqual $Before.AddHours($Hours).AddSeconds(-1)
        $Next | Should -BeLessOrEqual ([datetime]::UtcNow.AddHours($Hours).AddSeconds(1))
    }

    It 'returns 0 and queues nothing when no workload is due' {
        $Later = [datetime]::UtcNow.AddDays(1).ToString('o')
        $script:Policies = @(New-CloudBackupPolicyRow -NextRuns ('{"exchange":"' + $Later + '","onedrive":"' + $Later + '"}'))

        Start-CloudBackupOrchestrator | Should -Be 0

        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly -ParameterFilter { $InputObject.OrchestratorName -ne 'CloudBackupPrune' }
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $TableName -eq 'Config' -and $null -ne $Entity.NextRuns }
    }

    It 'runs every workload of the given policy with -Force without moving its schedule, even when not due' {
        $Later = [datetime]::UtcNow.AddDays(1).ToString('o')
        $script:Policies = @(New-CloudBackupPolicyRow -NextRuns ('{"exchange":"' + $Later + '","onedrive":"' + $Later + '"}'))

        Start-CloudBackupOrchestrator -PolicyId $script:PolicyId -Force | Should -Be 'run-1'

        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $TableName -eq 'Config' }
        $script:PruneStarted.Count | Should -Be 0
        @($script:Started[0].Batch.Workload | Sort-Object) | Should -Be @('exchange', 'onedrive')
    }

    It 'limits a forced run to one workload' {
        $script:Policies = @(New-CloudBackupPolicyRow)

        Start-CloudBackupOrchestrator -PolicyId $script:PolicyId -Workload 'onedrive' -Force | Out-Null

        @($script:Started[0].Batch.Workload) | Should -Be @('onedrive')
    }

    It 'expands AllTenants to every tenant for every due workload' {
        $script:Policies = @(New-CloudBackupPolicyRow -Tenants '[{"type":"AllTenants"}]')

        Start-CloudBackupOrchestrator | Out-Null

        @($script:Started[0].Batch).Count | Should -Be 6
        @($script:Started[0].Batch.customerId | Sort-Object -Unique) | Should -Be @('c1', 'c2', 'c3')
        Should -Invoke New-CippQueueEntry -ParameterFilter { $TotalTasks -eq 6 }
    }

    It 'expands tenant groups through Expand-CIPPTenantGroups and drops unknown tenants' {
        $script:Policies = @(New-CloudBackupPolicyRow -Workloads '["exchange"]' -Tenants '[{"type":"Group","id":"g1"},{"type":"Tenant","customerId":"c1"},{"type":"Tenant","customerId":"gone"}]')
        Mock Expand-CIPPTenantGroups {
            @(
                [pscustomobject]@{ value = 'fabrikam.com'; addedFields = [pscustomobject]@{ customerId = 'c2' }; type = 'Tenant' }
                [pscustomobject]@{ value = 'excluded.com'; addedFields = [pscustomobject]@{ customerId = 'excluded' }; type = 'Tenant' }
            )
        }

        Start-CloudBackupOrchestrator | Out-Null

        Should -Invoke Expand-CIPPTenantGroups -Times 1 -Exactly -ParameterFilter { $TenantFilter[0].type -eq 'Group' -and $TenantFilter[0].value -eq 'g1' }
        @($script:Started[0].Batch.customerId | Sort-Object) | Should -Be @('c1', 'c2')
    }

    It 'limits a forced run to the given tenant, and returns 0 for a tenant outside the policy' {
        $script:Policies = @(New-CloudBackupPolicyRow -Tenants '[{"type":"AllTenants"}]' -Workloads '["exchange"]')
        Start-CloudBackupOrchestrator -PolicyId $script:PolicyId -TenantFilter 'fabrikam.com' -Force | Out-Null
        @($script:Started[0].Batch.customerId) | Should -Be @('c2')

        $script:Policies = @(New-CloudBackupPolicyRow)
        Start-CloudBackupOrchestrator -PolicyId $script:PolicyId -TenantFilter 'fabrikam.com' -Force | Should -Be 0
        $script:Started.Count | Should -Be 1
    }

    It 'sets the versioned retention rule when it is missing, different or not versioned, and leaves a matching one alone' {
        $script:Policies = @(New-CloudBackupPolicyRow)
        Start-CloudBackupOrchestrator | Out-Null
        Should -Invoke Set-CIPPCloudBackupRetentionRule -Times 0 -Exactly

        Mock Get-CIPPCloudBackupRetentionRule { @{ Prefix = "$($script:PolicyId)/"; Days = 30; Mode = 'Versioned' } }
        Start-CloudBackupOrchestrator | Out-Null
        Should -Invoke Set-CIPPCloudBackupRetentionRule -Times 1 -Exactly -ParameterFilter { $RuleName -eq "cipp-$($script:PolicyId)" -and $Prefix -eq "$($script:PolicyId)/" -and $Days -eq 90 -and $Mode -eq 'Versioned' }

        Mock Get-CIPPCloudBackupRetentionRule { @{ Prefix = "$($script:PolicyId)/"; Days = 90; Mode = 'Current' } }
        Start-CloudBackupOrchestrator | Out-Null
        Should -Invoke Set-CIPPCloudBackupRetentionRule -Times 2 -Exactly

        Mock Get-CIPPCloudBackupRetentionRule { }
        Start-CloudBackupOrchestrator | Out-Null
        Should -Invoke Set-CIPPCloudBackupRetentionRule -Times 3 -Exactly
    }

    It 'still queues the backup when the retention rule check fails' {
        $script:Policies = @(New-CloudBackupPolicyRow)
        Mock Get-CIPPCloudBackupRetentionRule { throw 'AuthorizationFailed' }

        Start-CloudBackupOrchestrator | Should -Be 'run-1'

        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' -and $message -like '*retention rule*' }
    }

    It 'prunes runs older than the retention together with their per-owner results' {
        $script:Policies = @(New-CloudBackupPolicyRow -RetentionDays 30)
        $script:OldRuns = @([pscustomobject]@{ PartitionKey = $script:PolicyId; RowKey = 'old_c1_exchange' })
        $script:OwnerRows = @([pscustomobject]@{ PartitionKey = "$($script:PolicyId)_old_c1_exchange"; RowKey = 'u1' })
        $Expected = '{0:D19}' -f ([datetime]::MaxValue.Ticks - [datetime]::UtcNow.AddDays(-30).Ticks)

        Start-CloudBackupOrchestrator | Out-Null

        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $TableName -eq 'CloudBackupRuns' -and $Filter -match "^PartitionKey eq '11111111-1111-1111-1111-111111111111' and RowKey gt '(\d{19})'$" -and
            [math]::Abs([long]$Matches[1] - [long]$Expected) -lt [timespan]::TicksPerMinute -and ($Property -contains 'RowKey') -and ($Property -contains 'PartitionKey')
        }
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'CloudBackupRunOwners' -and $Filter -eq "PartitionKey eq '$($script:PolicyId)_old_c1_exchange'" -and ($Property -contains 'RowKey') }
        @($script:Removed.Where({ $_.Table -eq 'CloudBackupRunOwners' }).Entity.RowKey) | Should -Be @('u1')
        @($script:Removed.Where({ $_.Table -eq 'CloudBackupRuns' }).Entity.RowKey) | Should -Be @('old_c1_exchange')
    }

    It 'marks runs still running after 3 days as failed' {
        $script:Policies = @(New-CloudBackupPolicyRow)
        $script:StaleRuns = @([pscustomobject]@{ PartitionKey = $script:PolicyId; RowKey = 'stale_c1_exchange'; Status = 'Running' })

        Start-CloudBackupOrchestrator | Out-Null

        $Update = $script:RunWrites.Where({ $_.RowKey -eq 'stale_c1_exchange' })[0]
        $Update.Status | Should -Be 'Failed'
        Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'CloudBackupRuns' -and $OperationType -eq 'UpsertMerge' }
    }

    It 'prunes compare and restore jobs older than 30 days with their results' {
        $script:OldJobs = @([pscustomobject]@{ PartitionKey = 'CloudBackupJob'; RowKey = 'job-1' })

        Start-CloudBackupOrchestrator | Out-Null

        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        @($script:RemovedJobs | ForEach-Object { "$($_.PartitionKey)/$($_.RowKey)" }) | Should -Be @('CloudBackupJob/job-1', 'CloudBackupJobResult/job-1')
    }

    It 'marks jobs still queued or running after 12 hours as failed' {
        $script:StuckJobs = @(
            [pscustomobject]@{ PartitionKey = 'CloudBackupJob'; RowKey = 'job-2'; Type = 'Provision'; Status = 'Running'; Error = ''; CompletedAt = ''; CreatedAt = [datetime]::UtcNow.AddHours(-13).ToString('o') }
            [pscustomobject]@{ PartitionKey = 'CloudBackupJob'; RowKey = 'job-3'; Type = 'Provision'; Status = 'Running'; Error = ''; CompletedAt = ''; CreatedAt = [datetime]::UtcNow.AddHours(-1).ToString('o') }
        )

        Start-CloudBackupOrchestrator | Out-Null

        $script:JobWrites.Count | Should -Be 1
        $script:JobWrites[0].RowKey | Should -Be 'job-2'
        $script:JobWrites[0].Status | Should -Be 'Failed'
    }

    It 'queues the cleanup of old restore and export jobs and of expired exports instead of deleting their rows' {
        $script:OldJobs = @(
            [pscustomobject]@{ PartitionKey = 'CloudBackupJob'; RowKey = 'job-1'; Type = 'Compare' }
            [pscustomobject]@{ PartitionKey = 'CloudBackupJob'; RowKey = 'job-4'; Type = 'Restore' }
            [pscustomobject]@{ PartitionKey = 'CloudBackupJob'; RowKey = 'job-5'; Type = 'Export'; CleanupQueuedAt = [datetime]::UtcNow.AddHours(-1).ToString('o') }
        )
        Mock Get-CIPPAzDataTableEntity { @([pscustomobject]@{ PartitionKey = 'CloudBackupJob'; RowKey = 'job-6' }) } -ParameterFilter { $TableName -eq 'CloudBackupJobs' -and $Filter -like "*Type eq 'Export'*ExpiresAt lt*" }
        $script:CleanupStarted = [System.Collections.Generic.List[object]]::new()
        Mock Start-CIPPOrchestrator { $script:CleanupStarted.Add($InputObject) } -ParameterFilter { $InputObject.OrchestratorName -eq 'CloudBackupJobCleanup' }

        Start-CloudBackupOrchestrator | Out-Null

        @($script:RemovedJobs | ForEach-Object { "$($_.PartitionKey)/$($_.RowKey)" }) | Should -Be @('CloudBackupJob/job-1', 'CloudBackupJobResult/job-1')
        @($script:CleanupStarted[0].Batch | ForEach-Object { "$($_.JobId):$($_.Scope)" }) | Should -Be @('job-4:All', 'job-6:Export')
        @(@($script:JobWrites[0]).RowKey) | Should -Be @('job-4', 'job-6')
    }

    It 'queues a stalled restore again up to 3 times and fails a stalled export' {
        $Old = [datetime]::UtcNow.AddHours(-7).ToString('o')
        $script:StuckJobs = @(
            [pscustomobject]@{ PartitionKey = 'CloudBackupJob'; RowKey = 'job-7'; Type = 'Restore'; Status = 'Running'; SourceTenant = 'contoso.com'; UpdatedAt = $Old; Attempts = 1; CreatedAt = $Old; Error = ''; CompletedAt = '' }
            [pscustomobject]@{ PartitionKey = 'CloudBackupJob'; RowKey = 'job-8'; Type = 'RestorePreview'; Status = 'Running'; UpdatedAt = $Old; Attempts = 3; CreatedAt = $Old; Error = ''; CompletedAt = '' }
            [pscustomobject]@{ PartitionKey = 'CloudBackupJob'; RowKey = 'job-9'; Type = 'Export'; Status = 'Running'; UpdatedAt = [datetime]::UtcNow.AddHours(-25).ToString('o'); CreatedAt = $Old; Error = ''; CompletedAt = '' }
            [pscustomobject]@{ PartitionKey = 'CloudBackupJob'; RowKey = 'job-10'; Type = 'Restore'; Status = 'Running'; UpdatedAt = [datetime]::UtcNow.AddHours(-1).ToString('o'); CreatedAt = [datetime]::UtcNow.AddDays(-2).ToString('o'); Error = ''; CompletedAt = '' }
        )
        $script:Requeued = [System.Collections.Generic.List[object]]::new()
        Mock Start-CIPPOrchestrator { $script:Requeued.Add($InputObject) } -ParameterFilter { $InputObject.OrchestratorName -like 'CloudBackupRestore_*' }

        Start-CloudBackupOrchestrator | Out-Null

        $script:Requeued.Count | Should -Be 1
        $script:Requeued[0].Batch[0].JobId | Should -Be 'job-7'
        $script:Requeued[0].Batch[0].FunctionName | Should -Be 'CloudBackupRestore'
        @($script:JobWrites).Where({ $_.RowKey -eq 'job-7' })[0].Attempts | Should -Be 2
        @($script:JobWrites).Where({ $_.RowKey -eq 'job-8' })[0].Status | Should -Be 'Failed'
        @($script:JobWrites).Where({ $_.RowKey -eq 'job-9' })[0].Error | Should -BeLike '*Run the export again*'
        @($script:JobWrites).Where({ $_.RowKey -eq 'job-10' }).Count | Should -Be 0
    }

    It 'does not prune jobs on a forced run of one policy, and keeps backing up when pruning fails' {
        $script:Policies = @(New-CloudBackupPolicyRow)
        Start-CloudBackupOrchestrator -PolicyId $script:PolicyId -Force | Out-Null
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $TableName -eq 'CloudBackupJobs' }

        Mock Get-CIPPAzDataTableEntity { throw 'table down' } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Start-CloudBackupOrchestrator | Should -Be 'run-1'
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' -and $message -like '*jobs*' }
    }

    It 'skips a policy whose destination is gone' {
        $script:Policies = @(New-CloudBackupPolicyRow)
        Mock Get-CIPPCloudBackupDestination { }

        Start-CloudBackupOrchestrator | Should -BeFalse

        $script:Started.Count | Should -Be 0
    }

    It 'queues pruning of expired versions once a day for enabled policies on Azure Blob destinations, before any backup is due' {
        $Later = [datetime]::UtcNow.AddDays(1).ToString('o')
        $NotDue = '{"exchange":"' + $Later + '","onedrive":"' + $Later + '"}'
        $script:Policies = @(
            New-CloudBackupPolicyRow -Name 'Never pruned' -NextRuns $NotDue
            (New-CloudBackupPolicyRow -Id '33333333-3333-3333-3333-333333333333' -Name 'Pruned yesterday' -NextRuns $NotDue) | Add-Member -NotePropertyName LastPrunedAt -NotePropertyValue ([datetime]::UtcNow.AddHours(-25).ToString('o')) -PassThru
            (New-CloudBackupPolicyRow -Id '44444444-4444-4444-4444-444444444444' -Name 'Pruned today' -NextRuns $NotDue) | Add-Member -NotePropertyName LastPrunedAt -NotePropertyValue ([datetime]::UtcNow.AddHours(-2).ToString('o')) -PassThru
            New-CloudBackupPolicyRow -Id '55555555-5555-5555-5555-555555555555' -Name 'Off' -Enabled $false -NextRuns $NotDue
            New-CloudBackupPolicyRow -Id '66666666-6666-6666-6666-666666666666' -Name 'S3' -DestinationId '77777777-7777-7777-7777-777777777777' -NextRuns $NotDue
        )
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Id = $Id; Name = 'S3'; Provider = 'S3' } } -ParameterFilter { $Id -eq '77777777-7777-7777-7777-777777777777' }
        $script:Order = [System.Collections.Generic.List[string]]::new()
        Mock Add-CIPPAzDataTableEntity { $script:ConfigWrites.Add($Entity); $script:Order.Add('mark') } -ParameterFilter { $TableName -eq 'Config' }
        Mock Start-CIPPOrchestrator { $script:PruneStarted.Add($InputObject); $script:Order.Add('prune') } -ParameterFilter { $InputObject.OrchestratorName -eq 'CloudBackupPrune' }

        Start-CloudBackupOrchestrator | Should -Be 0

        @($script:Order) | Should -Be @('mark', 'prune')
        $script:PruneStarted.Count | Should -Be 1
        @($script:PruneStarted[0].Batch.FunctionName | Select-Object -Unique) | Should -Be @('CloudBackupPrune')
        @($script:PruneStarted[0].Batch.PolicyId | Sort-Object) | Should -Be @('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333')
        $Marks = @($script:ConfigWrites[0])
        @($Marks.RowKey | Sort-Object) | Should -Be @('11111111-1111-1111-1111-111111111111', '33333333-3333-3333-3333-333333333333')
        foreach ($Mark in $Marks) { ([datetimeoffset]::Parse($Mark.LastPrunedAt).UtcDateTime - [datetime]::UtcNow).Duration().TotalMinutes | Should -BeLessThan 1 }
        $script:Started.Count | Should -Be 0
    }

    It 'still backs up when pruning cannot be queued' {
        $script:Policies = @(New-CloudBackupPolicyRow)
        Mock Start-CIPPOrchestrator { throw 'queue down' } -ParameterFilter { $InputObject.OrchestratorName -eq 'CloudBackupPrune' }

        Start-CloudBackupOrchestrator | Should -Be 'run-1'
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' -and $message -like '*expired*' }
    }
}

Describe 'Start-CloudBackupOrchestrator index maintenance' {
    BeforeEach {
        $Later = [datetime]::UtcNow.AddDays(1).ToString('o')
        $NotDue = '{"exchange":"' + $Later + '","onedrive":"' + $Later + '"}'
        $script:Policies = @(
            (New-CloudBackupPolicyRow -NextRuns $NotDue) | Add-Member -NotePropertyName LastPrunedAt -NotePropertyValue ([datetime]::UtcNow.ToString('o')) -PassThru
            New-CloudBackupPolicyRow -Id '55555555-5555-5555-5555-555555555555' -Name 'Off' -Enabled $false -NextRuns $NotDue
        )
        $script:StateRows = @(
            [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_u1'; Status = 'Idle'; LastCompactedAt = $null }
            [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'onedrive_u_2'; Status = 'Error'; LastCompactedAt = [datetime]::UtcNow.AddHours(-30).ToString('o') }
            [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_u3'; Status = 'Idle'; LastCompactedAt = [datetime]::UtcNow.AddHours(-2).ToString('o') }
            [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c2"; RowKey = 'sharepoint_contoso.sharepoint.com,a,b'; Status = 'Running'; LastCompactedAt = $null }
        )
        $script:StateWrites = [System.Collections.Generic.List[object]]::new()
        $script:Maintenance = [System.Collections.Generic.List[object]]::new()
        $script:Order = [System.Collections.Generic.List[string]]::new()
        Mock Get-CIPPAzDataTableEntity { $script:Policies } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity { $script:StateRows } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Get-CIPPAzDataTableEntity { } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Add-CIPPAzDataTableEntity { foreach ($Row in @($Entity)) { $script:StateWrites.Add($Row) }; $script:Order.Add('mark') } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Start-CIPPOrchestrator { $script:Maintenance.Add($InputObject); $script:Order.Add('queue') } -ParameterFilter { $InputObject.OrchestratorName -eq 'CloudBackupIndexMaintenance' }
        Mock Start-CIPPOrchestrator { }
        Mock Get-Tenants { $script:CloudBackupTenants }
        Mock Write-LogMessage { }
    }

    It 'queues owners not compacted in the last day, skipping running owners, and marks them first' {
        Start-CloudBackupOrchestrator | Out-Null

        @($script:Order) | Should -Be @('mark', 'queue')
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $TableName -eq 'CloudBackupState' -and $Filter -eq "PartitionKey ge '$($script:PolicyId)_' and PartitionKey lt '$($script:PolicyId)``'" -and
            ($Property -contains 'PartitionKey') -and ($Property -contains 'RowKey') -and ($Property -contains 'LastCompactedAt') -and ($Property -notcontains 'State')
        }
        $Batch = @($script:Maintenance[0].Batch)
        @($Batch.RowKey) | Should -Be @('exchange_u1', 'onedrive_u_2')
        $Batch[0].FunctionName | Should -Be 'CloudBackupIndexMaintenance'
        $Batch[0].PolicyId | Should -Be $script:PolicyId
        $Batch[0].customerId | Should -Be 'c1'
        $Batch[0].Workload | Should -Be 'exchange'
        $Batch[0].OwnerKey | Should -Be 'u1'
        $Batch[1].Workload | Should -Be 'onedrive'
        $Batch[1].OwnerKey | Should -Be 'u_2'
        @($script:StateWrites.RowKey) | Should -Be @('exchange_u1', 'onedrive_u_2')
        foreach ($Write in $script:StateWrites) { ([datetimeoffset]::Parse($Write.LastCompactedAt).UtcDateTime - [datetime]::UtcNow).Duration().TotalMinutes | Should -BeLessThan 1 }
        Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'CloudBackupState' -and $OperationType -eq 'UpsertMerge' }
    }

    It 'queues at most 200 owners per run' {
        $script:StateRows = @(foreach ($i in 1..250) { [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = "exchange_u$i"; Status = 'Idle' } })
        Start-CloudBackupOrchestrator | Out-Null
        @($script:Maintenance[0].Batch).Count | Should -Be 200
        $script:StateWrites.Count | Should -Be 200
    }

    It 'queues nothing on a forced run of one policy' {
        Start-CloudBackupOrchestrator -PolicyId $script:PolicyId -Force | Out-Null
        $script:Maintenance.Count | Should -Be 0
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $TableName -eq 'CloudBackupState' }
    }

    It 'warns and carries on when the maintenance cannot be queued' {
        Mock Start-CIPPOrchestrator { throw 'queue down' } -ParameterFilter { $InputObject.OrchestratorName -eq 'CloudBackupIndexMaintenance' }
        { Start-CloudBackupOrchestrator } | Should -Not -Throw
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Warning' -and $message -like '*index maintenance*' }
    }
}

Describe 'Cloud backup policy helpers' {
    It 'Get-CIPPCloudBackupPolicy parses JSON columns, keeps next runs as ISO strings and ignores ids that are not GUIDs' {
        Mock Get-CIPPAzDataTableEntity { New-CloudBackupPolicyRow -Encryption $true -KeyIds '["k1","k2"]' -Tenants '[]' -Exclusions '{"Users":["u1"],"Groups":[],"Sites":["https://contoso.sharepoint.com/sites/hr"]}' }

        $Policy = Get-CIPPCloudBackupPolicy -Id '11111111-1111-1111-1111-111111111111'
        $Policy.Id | Should -Be '11111111-1111-1111-1111-111111111111'
        @($Policy.Workloads) | Should -Be @('exchange', 'onedrive')
        $Policy.Schedules.onedrive | Should -Be '6h'
        $Policy.NextRuns.exchange | Should -BeOfType [string]
        $Policy.NextRuns.exchange | Should -Be '2026-01-01T00:00:00.0000000Z'
        @($Policy.Exclusions.Users) | Should -Be @('u1')
        @($Policy.Exclusions.Groups).Count | Should -Be 0
        @($Policy.Exclusions.Sites) | Should -Be @('https://contoso.sharepoint.com/sites/hr')
        @($Policy.KeyIds) | Should -Be @('k1', 'k2')
        $Policy.Tenants.Count | Should -Be 0
        $Policy.Encryption | Should -BeTrue
        $Policy.RetentionDays | Should -Be 90
        $Policy.PermissionStatus | Should -BeNullOrEmpty

        Get-CIPPCloudBackupPolicy -Id "x' or PartitionKey ne '" | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'Get-CIPPCloudBackupPolicy -IncludePermissionStatus reads the policy partition of CloudBackupPermissions' {
        Mock Get-CIPPAzDataTableEntity { New-CloudBackupPolicyRow } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ PartitionKey = '11111111-1111-1111-1111-111111111111'; RowKey = 'c1'; Status = 'Granted'; Message = ''; CheckedAt = '2026-11-19T00:00:00.0000000Z' }
        } -ParameterFilter { $TableName -eq 'CloudBackupPermissions' }

        $Policy = Get-CIPPCloudBackupPolicy -Id '11111111-1111-1111-1111-111111111111' -IncludePermissionStatus

        $Policy.PermissionStatus['c1'].Status | Should -Be 'Granted'
        $Policy.PermissionStatus['c1'].Message | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'CloudBackupPermissions' -and $Filter -eq "PartitionKey eq '11111111-1111-1111-1111-111111111111'" }
    }

    It 'Test-CIPPCloudBackupPolicyScope allows <Case>' -ForEach @(
        @{ Case = 'an unrestricted caller any target'; Allowed = @('AllTenants'); Tenants = @([pscustomobject]@{ type = 'AllTenants' }); Expected = $true }
        @{ Case = 'a restricted caller their own tenants'; Allowed = @('c1', 'c2'); Tenants = @([pscustomobject]@{ type = 'Tenant'; customerId = 'c1' }); Expected = $true }
        @{ Case = 'no other tenant'; Allowed = @('c1'); Tenants = @([pscustomobject]@{ type = 'Tenant'; customerId = 'c2' }); Expected = $false }
        @{ Case = 'no AllTenants target for a restricted caller'; Allowed = @('c1'); Tenants = @([pscustomobject]@{ type = 'AllTenants' }); Expected = $false }
        @{ Case = 'no group target for a restricted caller'; Allowed = @('c1'); Tenants = @([pscustomobject]@{ type = 'Group'; id = 'g1' }); Expected = $false }
        @{ Case = 'nothing to a caller with no tenants'; Allowed = @(); Tenants = @([pscustomobject]@{ type = 'Tenant'; customerId = 'c1' }); Expected = $false }
    ) {
        Test-CIPPCloudBackupPolicyScope -Tenants $Tenants -AllowedTenants $Allowed | Should -Be $Expected
    }
}
