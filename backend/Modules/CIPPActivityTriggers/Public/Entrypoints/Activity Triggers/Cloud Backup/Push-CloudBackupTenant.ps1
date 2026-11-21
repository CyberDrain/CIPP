function Push-CloudBackupTenant {
    <#
    .SYNOPSIS
        Starts one cloud backup run for a tenant and workload: one task per owner (mailbox, OneDrive, site, team or chat user)
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $PolicyId = "$($Item.PolicyId)"
    $TenantId = "$($Item.customerId)"
    $Workload = "$($Item.Workload)".ToLowerInvariant()
    $StartedAt = [datetime]::UtcNow
    $RowKey = '{0:D19}_{1}_{2}' -f ([datetime]::MaxValue.Ticks - $StartedAt.Ticks), $TenantId, $Workload
    $Warnings = [System.Collections.Generic.List[string]]::new()
    $Run = @{
        PartitionKey    = $PolicyId
        RowKey          = $RowKey
        RunId           = "$($PolicyId)_$RowKey"
        RunStamp        = $StartedAt.ToString('yyyyMMddTHHmmssZ')
        PolicyId        = $PolicyId
        PolicyName      = ''
        DestinationId   = ''
        TenantId        = $TenantId
        Tenant          = "$($Item.QueueName ?? $TenantId)"
        Workload        = $Workload
        Status          = 'Running'
        StartedAt       = $StartedAt.ToString('o')
        CompletedAt     = ''
        Owners          = 0
        OwnersSucceeded = 0
        OwnersFailed    = 0
        Items           = 0
        Bytes           = [int64]0
        Deleted         = 0
        Warnings        = '[]'
        Location        = "$PolicyId/$TenantId/$Workload/"
    }
    $RunsTable = $null

    try {
        $RunsTable = Get-CIPPTable -TableName 'CloudBackupRuns'
        Add-CIPPAzDataTableEntity @RunsTable -Entity $Run -Force

        $Policy = Get-CIPPCloudBackupPolicy -Id $PolicyId
        if (-not $Policy) { throw "Cloud backup policy $PolicyId no longer exists" }
        $Run.PolicyName = $Policy.Name
        $Run.DestinationId = "$($Policy.DestinationId)"
        if ($Policy.Workloads -notcontains $Workload) { throw "Policy $($Policy.Name) does not back up $Workload" }

        $Tenant = @(Get-Tenants -TenantFilter $TenantId)[0]
        if (-not $Tenant) { throw "Tenant $TenantId was not found or is excluded" }
        $Run.Tenant = $Tenant.defaultDomainName

        $Destination = Get-CIPPCloudBackupDestination -Id $Policy.DestinationId
        if (-not $Destination) { throw "Destination $($Policy.DestinationId) no longer exists" }

        $PermissionTable = Get-CIPPTable -TableName 'CloudBackupPermissions'
        $Permission = @(Get-CIPPAzDataTableEntity @PermissionTable -Filter "PartitionKey eq '$PolicyId' and RowKey eq '$TenantId'")[0]
        $CheckedAt = [datetimeoffset]::MinValue
        $Fresh = $Permission -and $Permission.Status -eq 'Granted' -and
        [datetimeoffset]::TryParse("$($Permission.CheckedAt)", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$CheckedAt) -and
        $CheckedAt.UtcDateTime -gt $StartedAt.AddDays(-7) -and
        @(if ($Permission.Workloads) { [CIPP.CippJson]::ConvertFromJson([string]$Permission.Workloads) }) -contains $Workload
        if (-not $Fresh) {
            $Grant = Grant-CIPPCloudBackupPermission -TenantFilter $TenantId -Workloads $Policy.Workloads
            Add-CIPPAzDataTableEntity @PermissionTable -Entity @{
                PartitionKey = $PolicyId
                RowKey       = $TenantId
                Status       = $Grant.Status
                Message      = "$($Grant.Message)"
                CheckedAt    = $Grant.CheckedAt
                Workloads    = [CIPP.CippJson]::ToJson($Policy.Workloads, 2) ?? (ConvertTo-Json -InputObject @($Policy.Workloads) -Compress)
            } -Force
            if ($Grant.Status -ne 'Granted') { $Warnings.Add("Permissions: $($Grant.Message)") }
        }

        $Owners = @(Get-CIPPCloudBackupOwnerList -TenantFilter $Tenant.defaultDomainName -Workload $Workload -Exclusions $Policy.Exclusions)
        $Run.Owners = $Owners.Count

        if ($Owners.Count -gt 0) {
            try {
                $UnsafeOwnerChars = "[/\\#?'\u0000-\u001F\u007F-\u009F]"
                $Current = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                foreach ($Owner in $Owners) { [void]$Current.Add("$($Workload)_$("$($Owner.OwnerId)" -replace $UnsafeOwnerChars, '_')") }
                $StateTable = Get-CIPPTable -TableName 'CloudBackupState'
                $StateFilter = "PartitionKey eq '$($Policy.Id)_$($Tenant.customerId)' and RowKey ge '$($Workload)_' and RowKey lt '$Workload$([char]0x60)'"
                $Leavers = foreach ($Row in @(Get-CIPPAzDataTableEntity @StateTable -Filter $StateFilter -Property PartitionKey, RowKey, OwnerId, OwnerType, DisplayName, Removed)) {
                    if (-not $Current.Contains("$($Row.RowKey)") -and "$($Row.Removed)" -ne 'True') { $Row }
                }
                $Leavers = @($Leavers)
                if ($Leavers.Count -gt 0) {
                    $StillInTenant = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                    if (@($Policy.Exclusions.Users).Count + @($Policy.Exclusions.Groups).Count + @($Policy.Exclusions.Sites).Count -gt 0) {
                        $OwnerNames = @{ exchange = 'Exchange'; onedrive = 'OneDrive'; sharepoint = 'SharePoint'; teams = 'Teams' }
                        foreach ($Owner in @(& "Get-CIPPCloudBackup$($OwnerNames[$Workload])Owner" -TenantFilter $Tenant.defaultDomainName)) {
                            if ($Owner) { [void]$StillInTenant.Add("$($Workload)_$("$($Owner.OwnerId)" -replace $UnsafeOwnerChars, '_')") }
                        }
                    }
                    $RemovedBatch = foreach ($Row in $Leavers) {
                        [pscustomobject]@{
                            FunctionName = 'CloudBackupOwnerRemoved'
                            PolicyId     = $PolicyId
                            customerId   = $TenantId
                            Workload     = $Workload
                            OwnerId      = "$($Row.OwnerId)"
                            OwnerType    = "$($Row.OwnerType)"
                            DisplayName  = "$($Row.DisplayName)"
                            Reason       = if ($StillInTenant.Contains("$($Row.RowKey)")) { 'Excluded' } else { 'Removed' }
                            QueueName    = "$($Tenant.defaultDomainName) - $($Row.DisplayName ?? $Row.OwnerId) (removed)"
                        }
                    }
                    $null = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{
                            Batch            = @($RemovedBatch)
                            OrchestratorName = "CloudBackupRemoved_$($PolicyId)_$($TenantId)_$Workload"
                            SkipLog          = $true
                        })
                }
            } catch {
                $Warnings.Add("Could not check for removed owners: $((Get-CippException -Exception $_).NormalizedError)")
            }
        }

        $Run.Warnings =[CIPP.CippJson]::ToJson($Warnings, 2) ?? (ConvertTo-Json -InputObject @($Warnings) -Compress)
        if ($Owners.Count -eq 0) {
            $Run.Status = 'Succeeded'
            $Run.CompletedAt = [datetime]::UtcNow.ToString('o')
            Add-CIPPAzDataTableEntity @RunsTable -Entity $Run -Force
            return
        }
        Add-CIPPAzDataTableEntity @RunsTable -Entity $Run -Force

        if ($Item.QueueId) {
            try {
                Update-CippQueueEntry -RowKey $Item.QueueId -TotalTasks $Owners.Count -IncrementTotalTasks
            } catch {
                Write-Information "Could not update queue $($Item.QueueId): $($_.Exception.Message)"
            }
        }

        $Batch = foreach ($Owner in $Owners) {
            [pscustomobject]@{
                FunctionName      = 'CloudBackupOwner'
                PolicyId          = $PolicyId
                customerId        = $TenantId
                Workload          = $Workload
                OwnerId           = "$($Owner.OwnerId)"
                OwnerType         = "$($Owner.OwnerType)"
                DisplayName       = "$($Owner.DisplayName)"
                UserId            = $Owner.UserId
                UserPrincipalName = $Owner.UserPrincipalName
                SiteUrl           = $Owner.SiteUrl
                RunId             = $Run.RunId
                RunStamp          = $Run.RunStamp
                QueueId           = $Item.QueueId
                QueueName         = "$($Tenant.defaultDomainName) - $($Owner.DisplayName ?? $Owner.OwnerId)"
            }
        }
        $InputObject = [pscustomobject]@{
            Batch            = @($Batch)
            OrchestratorName = "CloudBackup_$($PolicyId)_$($TenantId)_$Workload"
            AllowCollision   = $false
            SkipLog          = $true
            PostExecution    = @{
                FunctionName = 'CloudBackupRunFinalise'
                Parameters   = @{ RunId = $Run.RunId }
            }
        }
        $Started = Start-CIPPOrchestrator -InputObject $InputObject
        if ("$Started" -like '*-Skipped') {
            $Warnings.Add('Skipped: the previous backup of this tenant and workload is still running')
            $Run.Status = 'Skipped'
            $Run.CompletedAt = [datetime]::UtcNow.ToString('o')
            $Run.Warnings = [CIPP.CippJson]::ToJson($Warnings, 2) ?? (ConvertTo-Json -InputObject @($Warnings) -Compress)
            Add-CIPPAzDataTableEntity @RunsTable -Entity $Run -Force
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Warnings.Add($ErrorMessage.NormalizedError)
        $Run.Status = 'Failed'
        $Run.CompletedAt = [datetime]::UtcNow.ToString('o')
        $Run.Warnings = [CIPP.CippJson]::ToJson($Warnings, 2) ?? (ConvertTo-Json -InputObject @($Warnings) -Compress)
        try {
            $RunsTable = $RunsTable ?? (Get-CIPPTable -TableName 'CloudBackupRuns')
            Add-CIPPAzDataTableEntity @RunsTable -Entity $Run -Force
        } catch {
            Write-Information "Could not record cloud backup run $($Run.RunId): $($_.Exception.Message)"
        }
        Write-LogMessage -API 'CloudBackup' -tenant $Run.Tenant -tenantid $TenantId -message "Cloud backup $($Run.PolicyName) ($Workload) could not start: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
