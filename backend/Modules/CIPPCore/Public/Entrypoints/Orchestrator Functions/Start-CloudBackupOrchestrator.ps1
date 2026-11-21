function Start-CloudBackupOrchestrator {
    <#
    .SYNOPSIS
        Queues cloud backup runs for every policy, tenant and workload that is due
    .DESCRIPTION
        Picks the workloads of enabled policies whose NextRuns time has passed (or the given policy with -Force), moves
        NextRuns on before queueing, keeps the destination's versioned retention rule in line with the policy, prunes run
        history older than the policy's retention and queues one task per tenant and workload. Once a day per policy on an
        Azure Blob destination it also queues the removal of versions older than the retention.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$PolicyId,
        [string]$TenantFilter,
        [string]$Workload,
        [switch]$Force
    )

    try {
        $Now = [datetime]::UtcNow
        $Intervals = @{
            '4h'  = [timespan]::FromHours(4)
            '6h'  = [timespan]::FromHours(6)
            '12h' = [timespan]::FromHours(12)
            '1d'  = [timespan]::FromDays(1)
        }
        $DefaultSchedules = @{ exchange = '4h'; teams = '4h'; onedrive = '6h'; sharepoint = '6h' }

        if (-not $PolicyId) {
            try {
                $JobsTable = Get-CIPPTable -TableName 'CloudBackupJobs'
                $StoredJobTypes = @{ Restore = 'CloudBackupRestore'; RestorePreview = 'CloudBackupRestore'; Export = 'CloudBackupExport' }
                $CleanupBatch = [System.Collections.Generic.List[object]]::new()
                $CleanupQueued = [System.Collections.Generic.List[object]]::new()
                $OldJobs = [System.Collections.Generic.List[object]]::new()
                foreach ($Job in @(Get-CIPPAzDataTableEntity @JobsTable -Filter "PartitionKey eq 'CloudBackupJob' and CreatedAt lt '$($Now.AddDays(-30).ToString('o'))'" -Property PartitionKey, RowKey, Type, CleanupQueuedAt)) {
                    if (-not $StoredJobTypes.ContainsKey("$($Job.Type)")) { $OldJobs.Add($Job); continue }
                    if ($CleanupBatch.Count -ge 50 -or [string]::CompareOrdinal("$($Job.CleanupQueuedAt)", $Now.AddHours(-6).ToString('o')) -gt 0) { continue }
                    $CleanupBatch.Add([pscustomobject]@{ FunctionName = 'CloudBackupJobCleanup'; JobId = $Job.RowKey; Scope = 'All' })
                    $CleanupQueued.Add(@{ PartitionKey = 'CloudBackupJob'; RowKey = $Job.RowKey; CleanupQueuedAt = $Now.ToString('o') })
                }
                if ($OldJobs.Count -gt 0) {
                    $OldResults = foreach ($Job in $OldJobs) { @{ PartitionKey = 'CloudBackupJobResult'; RowKey = $Job.RowKey } }
                    Remove-CIPPAzDataTableEntity @JobsTable -Entity @(@($OldJobs) + @($OldResults)) -Force
                }
                foreach ($Job in @(Get-CIPPAzDataTableEntity @JobsTable -Filter "PartitionKey eq 'CloudBackupJob' and Type eq 'Export' and Status eq 'Completed' and ExpiresAt lt '$($Now.ToString('o'))' and ExportRemovedAt eq ''" -Property PartitionKey, RowKey, CleanupQueuedAt)) {
                    if ($CleanupBatch.Count -ge 50) { break }
                    if ([string]::CompareOrdinal("$($Job.CleanupQueuedAt)", $Now.AddHours(-6).ToString('o')) -gt 0) { continue }
                    $CleanupBatch.Add([pscustomobject]@{ FunctionName = 'CloudBackupJobCleanup'; JobId = $Job.RowKey; Scope = 'Export' })
                    $CleanupQueued.Add(@{ PartitionKey = 'CloudBackupJob'; RowKey = $Job.RowKey; CleanupQueuedAt = $Now.ToString('o') })
                }
                if ($CleanupBatch.Count -gt 0) {
                    Add-CIPPAzDataTableEntity @JobsTable -Entity @($CleanupQueued) -OperationType 'UpsertMerge'
                    $null = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{ Batch = @($CleanupBatch); OrchestratorName = 'CloudBackupJobCleanup'; SkipLog = $true })
                }

                $StuckJobs = @(Get-CIPPAzDataTableEntity @JobsTable -Filter "PartitionKey eq 'CloudBackupJob' and (Status eq 'Queued' or Status eq 'Running')")
                foreach ($Job in $StuckJobs) {
                    $Function = $StoredJobTypes["$($Job.Type)"]
                    if ($Function) {
                        $StaleHours = if ($Job.Type -eq 'Export') { 24 } else { 6 }
                        if ([string]::CompareOrdinal("$($Job.UpdatedAt)", $Now.AddHours(-$StaleHours).ToString('o')) -gt 0) { continue }
                        $Attempts = [int]($Job.Attempts -as [int])
                        if ($Job.Type -ne 'Export' -and $Attempts -lt 3) {
                            Add-CIPPAzDataTableEntity @JobsTable -Entity @{ PartitionKey = 'CloudBackupJob'; RowKey = $Job.RowKey; Attempts = $Attempts + 1; UpdatedAt = $Now.ToString('o') } -OperationType 'UpsertMerge'
                            $null = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{
                                    Batch            = @([pscustomobject]@{ FunctionName = $Function; JobId = $Job.RowKey; QueueName = "$($Job.SourceTenant)" })
                                    OrchestratorName = "$($Function)_$($Job.RowKey)"
                                    SkipLog          = $true
                                })
                            continue
                        }
                        $Job.Error = if ($Job.Type -eq 'Export') { 'The export stopped before it finished. Run the export again.' } else { 'The restore stopped making progress and was given up after 3 attempts' }
                    } else {
                        if (-not $Job.CreatedAt -or [string]::CompareOrdinal("$($Job.CreatedAt)", $Now.AddHours(-12).ToString('o')) -ge 0) { continue }
                        $Job.Error = 'The job did not finish within 12 hours'
                    }
                    $Job.Status = 'Failed'
                    $Job.CompletedAt = $Now.ToString('o')
                    Add-CIPPAzDataTableEntity @JobsTable -Entity $Job -Force
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'CloudBackup' -message "Could not remove old cloud backup jobs: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
            }
        }

        $Policies = @(if ($PolicyId) { Get-CIPPCloudBackupPolicy -Id $PolicyId } else { Get-CIPPCloudBackupPolicy })

        if (-not $PolicyId) {
            try {
                $Prune = foreach ($Policy in $Policies) {
                    if (-not $Policy.Enabled) { continue }
                    $LastPruned = [datetimeoffset]::MinValue
                    if ([datetimeoffset]::TryParse("$($Policy.LastPrunedAt)", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$LastPruned) -and $LastPruned.UtcDateTime -gt $Now.AddDays(-1)) { continue }
                    $Destination = Get-CIPPCloudBackupDestination -Id $Policy.DestinationId
                    if ($Destination.Provider -ne 'AzureBlob') { continue }
                    $Policy
                }
                $Prune = @($Prune)
                if ($Prune.Count -gt 0) {
                    $PruneConfig = Get-CIPPTable -TableName 'Config'
                    $PruneUpdates = foreach ($Policy in $Prune) { @{ PartitionKey = 'CloudBackupPolicy'; RowKey = $Policy.Id; LastPrunedAt = $Now.ToString('o') } }
                    Add-CIPPAzDataTableEntity @PruneConfig -Entity @($PruneUpdates) -OperationType 'UpsertMerge'
                    $PruneBatch = foreach ($Policy in $Prune) { [pscustomobject]@{ FunctionName = 'CloudBackupPrune'; PolicyId = $Policy.Id } }
                    $null = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{ Batch = @($PruneBatch); OrchestratorName = 'CloudBackupPrune'; SkipLog = $true })
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'CloudBackup' -message "Could not queue the removal of expired cloud backup versions: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
            }

            try {
                $MaxMaintenance = 200
                $StateTable = Get-CIPPTable -TableName 'CloudBackupState'
                $Maintenance = [System.Collections.Generic.List[object]]::new()
                foreach ($Policy in $Policies) {
                    if ($Maintenance.Count -ge $MaxMaintenance) { break }
                    if (-not $Policy.Enabled) { continue }
                    $StateFilter = "PartitionKey ge '$($Policy.Id)_' and PartitionKey lt '$($Policy.Id)$([char]0x60)'"
                    foreach ($Row in @(Get-CIPPAzDataTableEntity @StateTable -Filter $StateFilter -Property PartitionKey, RowKey, Status, LastCompactedAt)) {
                        if ($Maintenance.Count -ge $MaxMaintenance) { break }
                        if ("$($Row.Status)" -eq 'Running') { continue }
                        $LastCompacted = [datetimeoffset]::MinValue
                        if ([datetimeoffset]::TryParse("$($Row.LastCompactedAt)", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$LastCompacted) -and $LastCompacted.UtcDateTime -gt $Now.AddDays(-1)) { continue }
                        $Separator = "$($Row.RowKey)".IndexOf('_')
                        if ($Separator -lt 1) { continue }
                        $Maintenance.Add([pscustomobject]@{
                                FunctionName = 'CloudBackupIndexMaintenance'
                                PolicyId     = $Policy.Id
                                customerId   = "$($Row.PartitionKey)".Substring("$($Policy.Id)".Length + 1)
                                Workload     = "$($Row.RowKey)".Substring(0, $Separator)
                                OwnerKey     = "$($Row.RowKey)".Substring($Separator + 1)
                                PartitionKey = "$($Row.PartitionKey)"
                                RowKey       = "$($Row.RowKey)"
                            })
                    }
                }
                if ($Maintenance.Count -gt 0) {
                    $Marks = foreach ($Task in $Maintenance) { @{ PartitionKey = $Task.PartitionKey; RowKey = $Task.RowKey; LastCompactedAt = $Now.ToString('o') } }
                    Add-CIPPAzDataTableEntity @StateTable -Entity @($Marks) -OperationType 'UpsertMerge'
                    $null = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{ Batch = @($Maintenance); OrchestratorName = 'CloudBackupIndexMaintenance'; SkipLog = $true })
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'CloudBackup' -message "Could not queue cloud backup index maintenance: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
            }
        }
        $Due = foreach ($Policy in $Policies) {
            if (-not $Policy.Enabled -and -not ($Force -and $PolicyId)) { continue }
            $DueWorkloads = foreach ($Name in $Policy.Workloads) {
                if ($Workload -and $Name -ne $Workload) { continue }
                if ($Force -and $PolicyId) { $Name; continue }
                $NextRun = [datetimeoffset]::MinValue
                $Parsed = [datetimeoffset]::TryParse("$($Policy.NextRuns.$Name)", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$NextRun)
                if (-not $Parsed -or $NextRun.UtcDateTime -le $Now) { $Name }
            }
            $DueWorkloads = @($DueWorkloads)
            if ($DueWorkloads.Count -gt 0) { [pscustomobject]@{ Policy = $Policy; Workloads = $DueWorkloads } }
        }
        $Due = @($Due)
        if ($Due.Count -eq 0) {
            Write-Information 'No cloud backup policies are due'
            return 0
        }

        $ConfigTable = Get-CIPPTable -TableName 'Config'
        if (-not $Force) {
            $NextRunUpdates = foreach ($Entry in $Due) {
                $NextRuns = [ordered]@{}
                foreach ($Name in $Entry.Policy.Workloads) { if ($Entry.Policy.NextRuns.$Name) { $NextRuns[$Name] = "$($Entry.Policy.NextRuns.$Name)" } }
                foreach ($Name in $Entry.Workloads) {
                    $Interval = $Intervals["$($Entry.Policy.Schedules.$Name)"] ?? $Intervals[$DefaultSchedules[$Name] ?? '1d']
                    $NextRuns[$Name] = $Now.Add($Interval).ToString('o')
                }
                @{ PartitionKey = 'CloudBackupPolicy'; RowKey = $Entry.Policy.Id; NextRuns = [CIPP.CippJson]::ToJson($NextRuns, 2) ?? (ConvertTo-Json -InputObject $NextRuns -Compress) }
            }
            Add-CIPPAzDataTableEntity @ConfigTable -Entity @($NextRunUpdates) -OperationType 'UpsertMerge'
        }

        $TenantList = @(Get-Tenants)
        $DomainById = @{}
        foreach ($Tenant in $TenantList) { $DomainById[$Tenant.customerId] = $Tenant.defaultDomainName }
        $OnlyTenant = $null
        if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
            $OnlyTenant = (Get-CIPPTenantLookup -Tenants $TenantList)[$TenantFilter].customerId
            if (-not $OnlyTenant) {
                Write-LogMessage -API 'CloudBackup' -tenant $TenantFilter -message "Cloud backup: tenant $TenantFilter was not found" -sev Warning
                return 0
            }
        }

        $RunsTable = Get-CIPPTable -TableName 'CloudBackupRuns'
        $OwnersTable = Get-CIPPTable -TableName 'CloudBackupRunOwners'
        $Results = foreach ($Entry in $Due) {
            $Policy = $Entry.Policy
            try {
                $Destination = Get-CIPPCloudBackupDestination -Id $Policy.DestinationId -IncludeSecret
                if (-not $Destination) {
                    Write-LogMessage -API 'CloudBackup' -message "Cloud backup policy $($Policy.Name) skipped: its destination no longer exists" -sev Error
                    $false
                    continue
                }

                $RuleName = "cipp-$($Policy.Id)"
                $Prefix = "$($Policy.Id)/"
                try {
                    $Rule = Get-CIPPCloudBackupRetentionRule -Destination $Destination -RuleName $RuleName
                    if (-not $Rule -or $Rule.Prefix -ne $Prefix -or ($Rule.Days -as [int]) -ne $Policy.RetentionDays -or $Rule.Mode -ne 'Versioned') {
                        Set-CIPPCloudBackupRetentionRule -Destination $Destination -RuleName $RuleName -Prefix $Prefix -Days $Policy.RetentionDays -Mode 'Versioned'
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'CloudBackup' -message "Cloud backup policy $($Policy.Name): could not check the retention rule on $($Destination.Name): $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
                }

                $CutoffKey = '{0:D19}' -f ([datetime]::MaxValue.Ticks - $Now.AddDays(-$Policy.RetentionDays).Ticks)
                $OldRuns = @(Get-CIPPAzDataTableEntity @RunsTable -Filter "PartitionKey eq '$($Policy.Id)' and RowKey gt '$CutoffKey'" -Property PartitionKey, RowKey)
                foreach ($OldRun in $OldRuns) {
                    $OwnerRows = @(Get-CIPPAzDataTableEntity @OwnersTable -Filter "PartitionKey eq '$($OldRun.PartitionKey)_$($OldRun.RowKey)'" -Property PartitionKey, RowKey)
                    if ($OwnerRows.Count -gt 0) { Remove-CIPPAzDataTableEntity @OwnersTable -Entity $OwnerRows -Force }
                }
                if ($OldRuns.Count -gt 0) { Remove-CIPPAzDataTableEntity @RunsTable -Entity $OldRuns -Force }

                $StaleKey = '{0:D19}' -f ([datetime]::MaxValue.Ticks - $Now.AddDays(-3).Ticks)
                $StaleRuns = @(Get-CIPPAzDataTableEntity @RunsTable -Filter "PartitionKey eq '$($Policy.Id)' and RowKey gt '$StaleKey' and Status eq 'Running'" -Property PartitionKey, RowKey, Status)
                if ($StaleRuns.Count -gt 0) {
                    $StaleUpdates = foreach ($StaleRun in $StaleRuns) {
                        @{ PartitionKey = $StaleRun.PartitionKey; RowKey = $StaleRun.RowKey; Status = 'Failed'; CompletedAt = $Now.ToString('o'); Warnings = '["The run did not finish within 3 days"]' }
                    }
                    Add-CIPPAzDataTableEntity @RunsTable -Entity @($StaleUpdates) -OperationType 'UpsertMerge'
                }

                $TenantIds = @(Get-CIPPCloudBackupPolicyTenantId -Tenants $Policy.Tenants -TenantList $TenantList)
                if ($OnlyTenant) { $TenantIds = @($TenantIds.Where({ $_ -eq $OnlyTenant })) }
                if ($TenantIds.Count -eq 0) {
                    Write-LogMessage -API 'CloudBackup' -message "Cloud backup policy $($Policy.Name) has no tenants to back up" -sev Warning
                    continue
                }

                $Batch = foreach ($TenantId in $TenantIds) {
                    foreach ($Name in $Entry.Workloads) {
                        [pscustomobject]@{
                            FunctionName = 'CloudBackupTenant'
                            PolicyId     = $Policy.Id
                            customerId   = $TenantId
                            Workload     = $Name
                            QueueName    = $DomainById[$TenantId] ?? $TenantId
                        }
                    }
                }
                $Batch = @($Batch)
                $Queue = New-CippQueueEntry -Name "Cloud Backup - $($Policy.Name)" -TotalTasks $Batch.Count
                foreach ($Task in $Batch) { $Task.PSObject.Properties.Add([psnoteproperty]::new('QueueId', $Queue.RowKey)) }
                $InputObject = [pscustomobject]@{
                    Batch            = $Batch
                    OrchestratorName = "CloudBackupPlan_$($Policy.Id)"
                    SkipLog          = $true
                }
                if ($PSCmdlet.ShouldProcess($Policy.Name, 'Starting cloud backup')) {
                    Start-CIPPOrchestrator -InputObject $InputObject
                }
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'CloudBackup' -message "Could not start cloud backup policy $($Policy.Name): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
                $false
            }
        }
        $Results = @($Results)
        if ($Results.Count -eq 0) { return 0 }
        if ($Results.Count -eq 1) { return $Results[0] }
        return $Results
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CloudBackup' -message "Could not start cloud backups: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return $false
    }
}
