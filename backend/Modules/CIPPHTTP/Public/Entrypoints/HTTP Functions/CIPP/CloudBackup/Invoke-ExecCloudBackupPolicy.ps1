function Invoke-ExecCloudBackupPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackup.ReadWrite
    .SYNOPSIS
        Add, edit, delete a cloud backup policy, rotate its key or grant its permissions
    .DESCRIPTION
        Saves a cloud backup policy (tenants, workloads: Exchange, OneDrive, SharePoint, Teams, a schedule per workload, exclusions, retention, encryption). The destination must have versioning turned on; its lifecycle rule that removes older versions after the retention is set before the policy is saved, and the policy is not saved when that fails. After saving, CIPP grants its app the permissions the workloads need in every covered tenant in the background. GrantPermissions does that again for one or all tenants. Delete removes the policy and its lifecycle rule but keeps stored backups and keys. RotateKey creates a new encryption key for future backups.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Headers = $Request.Headers
    $Action = $Request.Body.Action
    $Id = $Request.Body.Id
    $Name = "$($Request.Body.Name)".Trim()
    $DestinationId = "$($Request.Body.DestinationId.value ?? $Request.Body.DestinationId)"
    # Tenant selector entries: { value, label, type: 'Tenant' | 'Group', addedFields: { customerId } }; value 'AllTenants' for all tenants
    $TenantInput = @($Request.Body.Tenants).Where({ $null -ne $_ })
    # Any of exchange, onedrive, sharepoint, teams
    $Workloads = @(foreach ($Entry in @($Request.Body.Workloads)) { if ($null -ne $Entry) { "$($Entry.value ?? $Entry)".ToLowerInvariant() } })
    # Object of workload -> 4h | 6h | 12h | 1d (OneDrive and SharePoint: 6h or longer)
    $ScheduleInput = $Request.Body.Schedules
    # Users (ids or UPNs) and groups (ids) whose members are not backed up, and site URLs that are not backed up
    $ExclusionInput = $Request.Body.Exclusions
    # GrantPermissions only: customerId of one tenant of the policy; all tenants when empty
    $GrantTenant = "$($Request.Body.TenantId)"
    $RetentionDays = if ($null -eq $Request.Body.RetentionDays -or "$($Request.Body.RetentionDays)" -eq '') { 90 } else { $Request.Body.RetentionDays -as [int] }
    $Encryption = $Request.Body.Encryption -eq $true
    $Enabled = $null -eq $Request.Body.Enabled -or $Request.Body.Enabled -eq $true
    $AllowedSchedules = @{
        exchange   = @('4h', '6h', '12h', '1d')
        teams      = @('4h', '6h', '12h', '1d')
        onedrive   = @('6h', '12h', '1d')
        sharepoint = @('6h', '12h', '1d')
    }
    $DefaultSchedules = @{ exchange = '4h'; teams = '4h'; onedrive = '6h'; sharepoint = '6h' }

    if ($Action -notin @('Add', 'Edit', 'Delete', 'RotateKey', 'GrantPermissions')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Action must be Add, Edit, Delete, RotateKey or GrantPermissions' }
            })
    }
    if ($Action -ne 'Add' -and -not ($Id -as [guid])) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Id must be a policy id (GUID)' }
            })
    }

    $Schedules = [ordered]@{}
    $Exclusions = $null
    if ($Action -in @('Add', 'Edit')) {
        foreach ($Workload in $Workloads) {
            if (-not $AllowedSchedules.ContainsKey($Workload)) { continue }
            $Value = $ScheduleInput.$Workload
            $Schedules[$Workload] = if ($null -eq $Value -or "$($Value.value ?? $Value)" -eq '') { $DefaultSchedules[$Workload] } else { "$($Value.value ?? $Value)" }
        }
        $ExcludedUsers = @(foreach ($Entry in @($ExclusionInput.Users)) { if ($null -ne $Entry -and "$($Entry.value ?? $Entry)".Trim()) { "$($Entry.value ?? $Entry)".Trim() } })
        $ExcludedGroups = @(foreach ($Entry in @($ExclusionInput.Groups)) { if ($null -ne $Entry -and "$($Entry.value ?? $Entry)".Trim()) { "$($Entry.value ?? $Entry)".Trim() } })
        $ExcludedSites = @(foreach ($Entry in @($ExclusionInput.Sites)) { if ($null -ne $Entry -and "$($Entry.value ?? $Entry)".Trim()) { "$($Entry.value ?? $Entry)".Trim().TrimEnd('/') } })
        $Exclusions = [ordered]@{ Users = $ExcludedUsers; Groups = $ExcludedGroups; Sites = $ExcludedSites }

        $Problem = if (-not $Name) {
            'Name is required'
        } elseif (-not ($DestinationId -as [guid])) {
            'Choose a destination'
        } elseif ($TenantInput.Count -eq 0) {
            'Choose at least one tenant'
        } elseif (@($TenantInput.Where({ $_.type -notin @('Tenant', 'Group') -or -not $_.value })).Count -gt 0) {
            'Tenants must be tenant or tenant group selections'
        } elseif ($Workloads.Count -eq 0) {
            'Choose at least one of Exchange, OneDrive, SharePoint or Teams'
        } elseif (@($Workloads.Where({ -not $AllowedSchedules.ContainsKey($_) })).Count -gt 0) {
            'Workloads must be from: exchange, onedrive, sharepoint, teams'
        } elseif (@($Schedules.Keys.Where({ $AllowedSchedules[$_] -notcontains $Schedules[$_] })).Count -gt 0) {
            'Exchange and Teams can run every 4h, 6h, 12h or 1d; OneDrive and SharePoint every 6h, 12h or 1d'
        } elseif (@($ExcludedSites.Where({ $_ -notmatch '^https://[^/\s]+' })).Count -gt 0) {
            'Excluded sites must be full site URLs starting with https://'
        } elseif ($null -eq $RetentionDays -or $RetentionDays -lt 7 -or $RetentionDays -gt 3650) {
            'Retention days must be a whole number from 7 to 3650'
        }
        if ($Problem) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = $Problem }
                })
        }
        $Workloads = @($Workloads | Select-Object -Unique)
    }

    try {
        $AllowedTenants = @(Test-CIPPAccess -Request $Request -TenantList)
        $Table = Get-CIPPTable -TableName 'Config'
        $PermissionTable = Get-CIPPTable -TableName 'CloudBackupPermissions'

        $Existing = $null
        if ($Action -ne 'Add') {
            $Existing = Get-CIPPCloudBackupPolicy -Id $Id
            if (-not $Existing) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body       = @{ Results = "Policy $Id was not found" }
                    })
            }
            if (-not (Test-CIPPCloudBackupPolicyScope -Tenants $Existing.Tenants -AllowedTenants $AllowedTenants)) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::Forbidden
                        Body       = @{ Results = 'This policy includes tenants you do not have access to' }
                    })
            }
        }

        $GrantTenantIds = @()
        $GrantPolicy = $null
        switch ($Action) {
            'Delete' {
                try {
                    $Destination = Get-CIPPCloudBackupDestination -Id $Existing.DestinationId -IncludeSecret
                    if ($Destination) { Remove-CIPPCloudBackupRetentionRule -Destination $Destination -RuleName "cipp-$Id" }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message "Could not remove the retention rule for cloud backup policy $($Existing.Name): $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
                }
                Remove-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'CloudBackupPolicy'; RowKey = "$Id" } -Force
                $PermissionRows = @(Get-CIPPAzDataTableEntity @PermissionTable -Filter "PartitionKey eq '$Id'" -Property PartitionKey, RowKey)
                if ($PermissionRows.Count -gt 0) { Remove-CIPPAzDataTableEntity @PermissionTable -Entity $PermissionRows -Force }
                Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message "Deleted cloud backup policy $($Existing.Name)" -sev Info
                $Result = "Deleted policy $($Existing.Name). Backups already stored stay in the destination until its retention rule removes them."
            }
            'RotateKey' {
                if (-not $Existing.Encryption) {
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body       = @{ Results = "Encryption is off for policy $($Existing.Name)" }
                        })
                }
                $KeyId = New-CIPPCloudBackupKey
                $KeyIds = @(@($Existing.KeyIds).Where({ $_ }); "$KeyId")
                Add-CIPPAzDataTableEntity @Table -Entity @{
                    PartitionKey = 'CloudBackupPolicy'
                    RowKey       = "$Id"
                    CurrentKeyId = "$KeyId"
                    KeyIds       = [CIPP.CippJson]::ToJson($KeyIds, 2) ?? (ConvertTo-Json -InputObject $KeyIds -Compress)
                } -OperationType 'UpsertMerge'
                Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message "Rotated the encryption key of cloud backup policy $($Existing.Name)" -sev Info
                $Result = "Created a new encryption key for policy $($Existing.Name). New backups use it; older backups keep their key."
            }
            'GrantPermissions' {
                $Covered = @(Get-CIPPCloudBackupPolicyTenantId -Tenants $Existing.Tenants)
                if ($GrantTenant) {
                    $GrantTenantId = (Get-CIPPTenantLookup)[$GrantTenant].customerId
                    if (-not $GrantTenantId -or $Covered -notcontains $GrantTenantId) {
                        return ([HttpResponseContext]@{
                                StatusCode = [HttpStatusCode]::BadRequest
                                Body       = @{ Results = "Policy $($Existing.Name) does not back up $GrantTenant" }
                            })
                    }
                    $Covered = @($GrantTenantId)
                }
                if ($Covered.Count -eq 0) {
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body       = @{ Results = "Policy $($Existing.Name) has no tenants" }
                        })
                }
                $GrantTenantIds = $Covered
                $GrantPolicy = $Existing
                $Result = "Granting permissions for policy $($Existing.Name) in $($Covered.Count) $(if ($Covered.Count -eq 1) { 'tenant' } else { 'tenants' }). The status updates when it finishes."
            }
            default {
                $Lookup = Get-CIPPTenantLookup
                $Unknown = [System.Collections.Generic.List[string]]::new()
                $StoredTenants = @(foreach ($Entry in $TenantInput) {
                        if ($Entry.type -eq 'Group') {
                            [ordered]@{ type = 'Group'; id = "$($Entry.value)" }
                        } elseif ($Entry.value -eq 'AllTenants') {
                            [ordered]@{ type = 'AllTenants' }
                        } else {
                            $CustomerId = $Entry.addedFields.customerId ?? $Lookup["$($Entry.value)"].customerId
                            if ($CustomerId) { [ordered]@{ type = 'Tenant'; customerId = "$CustomerId" } } else { $Unknown.Add("$($Entry.label ?? $Entry.value)") }
                        }
                    })
                if ($Unknown.Count -gt 0) {
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body       = @{ Results = "Unknown tenants: $($Unknown -join ', ')" }
                        })
                }
                if (-not (Test-CIPPCloudBackupPolicyScope -Tenants $StoredTenants -AllowedTenants $AllowedTenants)) {
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::Forbidden
                            Body       = @{ Results = 'You can only back up tenants you have access to; All Tenants and tenant groups need access to every tenant' }
                        })
                }

                $Destination = Get-CIPPCloudBackupDestination -Id $DestinationId -IncludeSecret
                if (-not $Destination) {
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body       = @{ Results = "Destination $DestinationId does not exist" }
                        })
                }
                if ($Destination.ImmutabilityDays -gt $RetentionDays) {
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body       = @{ Results = "Retention days must be at least $($Destination.ImmutabilityDays): destination $($Destination.Name) keeps every version for $($Destination.ImmutabilityDays) days, so older versions cannot be removed sooner." }
                        })
                }
                $Versioning = Get-CIPPCloudBackupVersioning -Destination $Destination
                if ("$Versioning" -ne 'Enabled') {
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body       = @{ Results = "Turn on versioning for destination $($Destination.Name) first (it is $(if ($Versioning) { "$Versioning".ToLower() } else { 'not available' })). Content backups keep earlier versions of changed and deleted items through versioning." }
                        })
                }

                if ($Action -eq 'Add') { $Id = [guid]::NewGuid().ToString() }
                try {
                    Set-CIPPCloudBackupRetentionRule -Destination $Destination -RuleName "cipp-$Id" -Prefix "$Id/" -Days $RetentionDays -Mode 'Versioned'
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    $Message = "Policy not saved: could not set the retention rule on destination $($Destination.Name): $($ErrorMessage.NormalizedError)"
                    Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message $Message -sev Error -LogData $ErrorMessage
                    return ([HttpResponseContext]@{
                            StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                            Body       = @{ Results = $Message }
                        })
                }
                if ($Existing -and $Existing.DestinationId -ne $DestinationId) {
                    try {
                        $OldDestination = Get-CIPPCloudBackupDestination -Id $Existing.DestinationId -IncludeSecret
                        if ($OldDestination) { Remove-CIPPCloudBackupRetentionRule -Destination $OldDestination -RuleName "cipp-$Id" }
                    } catch {
                        $ErrorMessage = Get-CippException -Exception $_
                        Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message "Could not remove the retention rule for cloud backup policy $Name from its previous destination: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
                    }
                }

                $CurrentKeyId = "$($Existing.CurrentKeyId)"
                $KeyIds = @(@($Existing.KeyIds).Where({ $_ }))
                if ($Encryption -and -not $CurrentKeyId) {
                    $CurrentKeyId = "$(New-CIPPCloudBackupKey)"
                    $KeyIds = @($KeyIds; $CurrentKeyId)
                }
                $NextRuns = [ordered]@{}
                foreach ($Workload in $Workloads) {
                    $NextRuns[$Workload] = if ($Existing.NextRuns.$Workload) { "$($Existing.NextRuns.$Workload)" } else { [datetime]::UtcNow.ToString('o') }
                }

                $Entity = @{
                    PartitionKey  = 'CloudBackupPolicy'
                    RowKey        = "$Id"
                    Name          = $Name
                    Enabled       = $Enabled
                    DestinationId = $DestinationId
                    Tenants       = [CIPP.CippJson]::ToJson($StoredTenants, 5) ?? (ConvertTo-Json -InputObject $StoredTenants -Depth 5 -Compress)
                    Workloads     = [CIPP.CippJson]::ToJson($Workloads, 2) ?? (ConvertTo-Json -InputObject $Workloads -Compress)
                    Schedules     = [CIPP.CippJson]::ToJson($Schedules, 2) ?? (ConvertTo-Json -InputObject $Schedules -Compress)
                    NextRuns      = [CIPP.CippJson]::ToJson($NextRuns, 2) ?? (ConvertTo-Json -InputObject $NextRuns -Compress)
                    Exclusions    = [CIPP.CippJson]::ToJson($Exclusions, 3) ?? (ConvertTo-Json -InputObject $Exclusions -Depth 3 -Compress)
                    RetentionDays = [int]$RetentionDays
                    Encryption    = $Encryption
                    CurrentKeyId  = $CurrentKeyId
                    KeyIds        = [CIPP.CippJson]::ToJson($KeyIds, 2) ?? (ConvertTo-Json -InputObject $KeyIds -Compress)
                }
                if ($Existing.LastPrunedAt) { $Entity.LastPrunedAt = $Existing.LastPrunedAt }
                if ($Existing.PruneStatus) { $Entity.PruneStatus = $Existing.PruneStatus }
                if ($Existing.PruneError) { $Entity.PruneError = $Existing.PruneError }
                if ($Existing.PruneSkipped) { $Entity.PruneSkipped = $Existing.PruneSkipped }
                Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
                Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message "Saved cloud backup policy $Name" -sev Info

                $GrantPolicy = [pscustomobject]@{ Id = "$Id"; Name = $Name; Workloads = $Workloads }
                $GrantTenantIds = @(Get-CIPPCloudBackupPolicyTenantId -Tenants $StoredTenants)
                $Result = "Saved policy $Name"
                if ($GrantTenantIds.Count -gt 0) { $Result = "$Result. Granting permissions in $($GrantTenantIds.Count) $(if ($GrantTenantIds.Count -eq 1) { 'tenant' } else { 'tenants' }) in the background." }
            }
        }

        if ($GrantTenantIds.Count -gt 0) {
            $WorkloadsJson = [CIPP.CippJson]::ToJson($GrantPolicy.Workloads, 2) ?? (ConvertTo-Json -InputObject @($GrantPolicy.Workloads) -Compress)
            $Pending = foreach ($TenantId in $GrantTenantIds) {
                @{ PartitionKey = "$($GrantPolicy.Id)"; RowKey = "$TenantId"; Status = 'Pending'; Message = ''; CheckedAt = [datetime]::UtcNow.ToString('o'); Workloads = $WorkloadsJson }
            }
            Add-CIPPAzDataTableEntity @PermissionTable -Entity @($Pending) -Force
            $DomainById = @{}
            foreach ($Tenant in @(Get-Tenants)) { $DomainById[$Tenant.customerId] = $Tenant.defaultDomainName }
            $Batch = foreach ($TenantId in $GrantTenantIds) {
                [pscustomobject]@{ FunctionName = 'CloudBackupGrant'; PolicyId = "$($GrantPolicy.Id)"; customerId = "$TenantId"; QueueName = $DomainById[$TenantId] ?? $TenantId }
            }
            $null = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{ Batch = @($Batch); OrchestratorName = "CloudBackupGrant_$($GrantPolicy.Id)"; SkipLog = $true })
        }
        $StatusCode = if ($Action -eq 'GrantPermissions') { [HttpStatusCode]::Accepted } else { [HttpStatusCode]::OK }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to $($Action.ToLower()) cloud backup policy: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
