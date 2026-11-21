function Invoke-ExecCloudBackupRestore {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackupRestore.ReadWrite
    .SYNOPSIS
        Preview or run a restore of backed-up mail or files
    .DESCRIPTION
        Queues a restore of items from a mailbox, OneDrive or SharePoint site backup at a point in time to the original owner or another user in the same tenant, and returns its JobId. Mode Preview makes no changes and shows what would happen to each item. Mode Apply needs the PreviewJobId of a completed preview with the same options, started by the same user in the last 60 minutes and not used for another restore. Teams backups can be exported but not restored. Poll ListCloudBackupJobs with the JobId for the results.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $PolicyId = "$($Request.Body.PolicyId)"
    # Tenant of the backup (customerId or default domain)
    $TenantId = "$($Request.Body.TenantId.value ?? $Request.Body.TenantId)"
    # exchange, onedrive or sharepoint
    $Workload = "$($Request.Body.Workload.value ?? $Request.Body.Workload)".ToLowerInvariant()
    # Owner id as returned by ListCloudBackupOwners
    $OwnerId = "$($Request.Body.OwnerId.value ?? $Request.Body.OwnerId)"
    # Recovery point (RunStamp) or date and time; the newest backup when empty
    $AsOf = "$($Request.Body.AsOf)".Trim()
    # Item keys to restore
    $Keys = @(foreach ($Key in @($Request.Body.Keys)) { if ($null -ne $Key -and "$Key" -ne '') { "$Key" } })
    # Folder paths to restore, including everything below them
    $Paths = @(foreach ($Path in @($Request.Body.Paths)) { if ($null -ne $Path) { "$Path".Trim('/') } })
    # User to restore to (id or UPN); the backed-up owner when empty
    $TargetOwnerId = "$($Request.Body.TargetOwnerId.value ?? $Request.Body.TargetOwnerId)".Trim()
    # RestoredFolder (default) or Original
    $Location = "$($Request.Body.Location.value ?? $Request.Body.Location)"
    # What to do when the item already exists: Skip (default), Overwrite or Copy
    $ConflictAction = "$($Request.Body.ConflictAction.value ?? $Request.Body.ConflictAction)"
    # Preview (no changes) or Apply
    $Mode = "$($Request.Body.Mode.value ?? $Request.Body.Mode)"
    # Id of the completed preview job, required for Apply
    $PreviewJobId = "$($Request.Body.PreviewJobId)"

    if (-not ($PolicyId -as [guid])) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'PolicyId must be a policy id (GUID)' } })
    }
    if (-not $TenantId -or $TenantId -eq 'AllTenants' -or $TenantId -like 'group:*') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'TenantId must be a single tenant' } })
    }
    if ($Workload -eq 'teams') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Teams backups can be exported but not restored' } })
    }
    if ($Workload -notin @('exchange', 'onedrive', 'sharepoint')) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Workload must be exchange, onedrive or sharepoint' } })
    }
    if (-not $OwnerId) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'OwnerId is required' } })
    }
    if ($Mode -notin @('Preview', 'Apply')) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Mode must be Preview or Apply' } })
    }
    if (-not $Location) { $Location = 'RestoredFolder' }
    if ($Location -notin @('RestoredFolder', 'Original')) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Location must be RestoredFolder or Original' } })
    }
    if (-not $ConflictAction) { $ConflictAction = 'Skip' }
    if ($ConflictAction -notin @('Skip', 'Overwrite', 'Copy')) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ConflictAction must be Skip, Overwrite or Copy' } })
    }
    if ($Keys.Count -gt 10000 -or $Paths.Count -gt 1000) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Select at most 10000 items and 1000 folders, or restore the parent folder instead' } })
    }
    $ParsedAsOf = [datetimeoffset]::MinValue
    if ($AsOf -and -not [datetimeoffset]::TryParseExact($AsOf, 'yyyyMMddTHHmmssZ', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$ParsedAsOf) -and
        -not [datetimeoffset]::TryParse($AsOf, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$ParsedAsOf)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'AsOf must be a recovery point or a date and time' } })
    }
    if ($Mode -eq 'Apply' -and -not ($PreviewJobId -as [guid])) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Run a restore preview first: Apply needs the PreviewJobId of a completed preview' } })
    }

    try {
        $Tenant = (Get-CIPPTenantLookup)[$TenantId]
        if (-not $Tenant) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = "Tenant $TenantId was not found" } })
        }
        $AllowedTenants = @(Test-CIPPAccess -Request $Request -TenantList)
        if ($AllowedTenants -notcontains 'AllTenants' -and $AllowedTenants -notcontains $Tenant.customerId) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Forbidden; Body = @{ Results = 'You do not have access to this tenant' } })
        }

        $Source = Resolve-CIPPCloudBackupJobSource -PolicyId $PolicyId -TenantId $Tenant.customerId -Workload $Workload -OwnerId $OwnerId -AsOf $AsOf -SkipRecoveryPoint:($Mode -eq 'Apply')
        $ToOriginal = -not $TargetOwnerId -or $TargetOwnerId -eq $OwnerId
        if ($ToOriginal -and $Source.Removed -and $Source.RemovedReason -ne 'Excluded') {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "$($Source.DisplayName) was removed from the tenant. Choose another user to restore to." } })
        }

        $Target = @{ OwnerId = ''; OwnerType = ''; UserPrincipalName = ''; SiteId = ''; DriveId = '' }
        if ($Workload -eq 'sharepoint' -and $ToOriginal) {
            $Response = @(New-GraphBulkRequest -tenantid $Tenant.defaultDomainName -asapp $true -Requests @(@{ id = 'site'; method = 'GET'; url = "sites/$([uri]::EscapeDataString($OwnerId))?`$select=id,webUrl" }))[0]
            if ($Response.status -eq 404) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "The site $($Source.DisplayName) no longer exists. Restore to a user's OneDrive instead." } })
            }
            if ([int]$Response.status -ge 400) { throw "Could not read the site $($Source.DisplayName): $($Response.body.error.message)" }
            $Target.OwnerId = $OwnerId
            $Target.OwnerType = 'Site'
            $Target.SiteId = $OwnerId
        } else {
            $UserRef = [uri]::EscapeDataString($(if ($TargetOwnerId) { $TargetOwnerId } else { $OwnerId }))
            $Requests = @(
                @{ id = 'user'; method = 'GET'; url = "users/$UserRef`?`$select=id,userPrincipalName,mail" }
                if ($Workload -ne 'exchange') { @{ id = 'drive'; method = 'GET'; url = "users/$UserRef/drive?`$select=id" } }
            )
            $Responses = @{}
            foreach ($Response in @(New-GraphBulkRequest -tenantid $Tenant.defaultDomainName -asapp $true -Requests $Requests)) { $Responses["$($Response.id)"] = $Response }
            $User = $Responses['user']
            if ($User.status -eq 404) {
                if ($ToOriginal) {
                    return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "$($Source.DisplayName) no longer exists in the tenant. Choose another user to restore to." } })
                }
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = "User $TargetOwnerId was not found in $($Tenant.defaultDomainName)" } })
            }
            if (-not $User -or [int]$User.status -ge 400) { throw "Could not read the user to restore to: $($User.body.error.message)" }
            $TargetName = $User.body.userPrincipalName ?? $User.body.id
            if ($Workload -eq 'exchange' -and -not $User.body.mail) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "$TargetName has no mailbox to restore to" } })
            }
            if ($Workload -ne 'exchange') {
                $Drive = $Responses['drive']
                if ($Drive.status -eq 404) {
                    return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "$TargetName has no OneDrive to restore to" } })
                }
                if (-not $Drive -or [int]$Drive.status -ge 400) { throw "Could not read the OneDrive of $($TargetName): $($Drive.body.error.message)" }
                $Target.DriveId = "$($Drive.body.id)"
            }
            $Target.OwnerId = "$($User.body.id)"
            $Target.OwnerType = 'User'
            $Target.UserPrincipalName = "$($User.body.userPrincipalName)"
        }

        $JobsTable = Get-CIPPTable -TableName 'CloudBackupJobs'
        $Now = [datetime]::UtcNow
        $Preview = $null
        if ($Mode -eq 'Apply') {
            $Preview = @(Get-CIPPAzDataTableEntity @JobsTable -Filter "PartitionKey eq 'CloudBackupJob' and RowKey eq '$([guid]$PreviewJobId)'")[0]
        }
        $RestoredFolderName = if ($Preview) { "$($Preview.RestoredFolderName)" } else { 'Restored {0:yyyy-MM-dd HH:mm}' -f $Now }

        $SortedKeys = [System.Collections.Generic.SortedSet[string]]::new([string[]]@($Keys), [System.StringComparer]::Ordinal)
        $SortedPaths = [System.Collections.Generic.SortedSet[string]]::new([string[]]@($Paths), [System.StringComparer]::Ordinal)
        $Parameters = [ordered]@{
            PolicyId           = "$([guid]$PolicyId)"
            TenantId           = "$($Tenant.customerId)"
            Workload           = $Workload
            OwnerId            = $OwnerId
            AsOf               = $AsOf
            Keys               = [string[]]@($SortedKeys)
            Paths              = [string[]]@($SortedPaths)
            TargetOwnerId      = $Target.OwnerId
            Location           = $Location
            RestoredFolderName = $RestoredFolderName
            ConflictAction     = $ConflictAction
        }
        $ParametersJson = [CIPP.CippJson]::ToJson($Parameters, 5) ?? (ConvertTo-Json -InputObject $Parameters -Depth 5 -Compress)
        $ParametersHash = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($ParametersJson))).ToLowerInvariant()
        $Principal = try { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json } catch { $null }
        $RequestedBy = if ($Request.Headers.'x-ms-client-principal-idp' -eq 'aad') { $Request.Headers.'x-ms-client-principal-name' } else { $Principal.userDetails ?? $Request.Headers.'x-ms-client-principal-name' ?? 'CIPP' }

        if ($Mode -eq 'Apply') {
            $PreviewCreated = [datetimeoffset]::MinValue
            $Refusal = if (-not $Preview -or $Preview.Type -ne 'RestorePreview') {
                'The preview was not found. Run a restore preview first.'
            } elseif ($Preview.Status -ne 'Completed') {
                'The preview has not completed successfully. Run a new preview.'
            } elseif ($Preview.AppliedJobId) {
                'This preview was already used for a restore. Run a new preview.'
            } elseif ("$($Preview.RequestedBy)" -ne "$RequestedBy") {
                'The preview was run by another user. Run your own preview first.'
            } elseif (-not [datetimeoffset]::TryParse("$($Preview.CreatedAt)", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$PreviewCreated) -or
                $PreviewCreated.UtcDateTime -lt $Now.AddMinutes(-60)) {
                'The preview is more than 60 minutes old. Run a new preview.'
            } elseif ("$($Preview.ParametersHash)" -ne $ParametersHash) {
                'The restore options differ from the preview. Run a new preview with these options.'
            }
            if ($Refusal) {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = $Refusal } })
            }
        }

        $JobId = [guid]::NewGuid().ToString()
        $Policy = $Source.Policy
        $Job = @{
            PartitionKey            = 'CloudBackupJob'
            RowKey                  = $JobId
            Type                    = if ($Mode -eq 'Apply') { 'Restore' } else { 'RestorePreview' }
            Status                  = 'Queued'
            RunId                   = ''
            CompareToRunId          = ''
            PolicyId                = "$($Policy.Id)"
            Workload                = $Workload
            SourceTenantId          = "$($Tenant.customerId)"
            SourceTenant            = "$($Tenant.defaultDomainName)"
            TargetTenantId          = "$($Tenant.customerId)"
            TargetTenant            = "$($Tenant.defaultDomainName)"
            SourceOwnerId           = $OwnerId
            SourceOwnerType         = $Source.OwnerType
            SourceOwnerName         = $Source.DisplayName
            SourceRemoved           = $Source.Removed
            TargetOwnerId           = $Target.OwnerId
            TargetOwnerType         = $Target.OwnerType
            TargetUserPrincipalName = $Target.UserPrincipalName
            TargetSiteId            = $Target.SiteId
            TargetDriveId           = $Target.DriveId
            AsOf                    = $AsOf
            RunStamp                = if ($Preview) { "$($Preview.RunStamp)" } else { $Source.RunStamp }
            Location                = $Location
            RestoredFolderName      = $RestoredFolderName
            ConflictAction          = $ConflictAction
            DataKeyId               = if ($Preview) { "$($Preview.DataKeyId)" } elseif ($Policy.Encryption -and $Policy.CurrentKeyId) { "$($Policy.CurrentKeyId)" } else { '' }
            ManifestJobId           = if ($Preview) { "$($Preview.ManifestJobId ?? $Preview.RowKey)" } else { $JobId }
            ManifestReady           = [bool]$Preview
            ItemCount               = if ($Preview) { [int]($Preview.ItemCount -as [int]) } else { 0 }
            Parameters              = $ParametersJson
            ParametersHash          = $ParametersHash
            PreviewJobId            = if ($Preview) { "$($Preview.RowKey)" } else { '' }
            RequestedBy             = "$RequestedBy"
            CreatedAt               = $Now.ToString('o')
            UpdatedAt               = $Now.ToString('o')
            StartedAt               = ''
            CompletedAt             = ''
            Attempts                = 0
            State                   = ''
            ResultCount             = 0
            ResultPages             = 0
            Summary                 = ''
            Error                   = ''
        }
        Add-CIPPAzDataTableEntity @JobsTable -Entity $Job -Force
        if ($Preview) {
            Add-CIPPAzDataTableEntity @JobsTable -Entity @{ PartitionKey = 'CloudBackupJob'; RowKey = $Preview.RowKey; AppliedJobId = $JobId } -OperationType 'UpsertMerge'
        }

        $Queued = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{
                Batch            = @([pscustomobject]@{ FunctionName = 'CloudBackupRestore'; JobId = $JobId; QueueName = $Tenant.defaultDomainName })
                OrchestratorName = "CloudBackupRestore_$JobId"
                SkipLog          = $true
            })
        if (-not $Queued) {
            Add-CIPPAzDataTableEntity @JobsTable -Entity @{ PartitionKey = 'CloudBackupJob'; RowKey = $JobId; Status = 'Failed'; Error = 'The restore could not be queued'; CompletedAt = [datetime]::UtcNow.ToString('o') } -OperationType 'UpsertMerge'
            if ($Preview) {
                Add-CIPPAzDataTableEntity @JobsTable -Entity @{ PartitionKey = 'CloudBackupJob'; RowKey = $Preview.RowKey; AppliedJobId = '' } -OperationType 'UpsertMerge'
            }
            throw 'The restore could not be queued'
        }

        $TargetName = if ($Target.OwnerType -eq 'Site') { $Source.DisplayName } else { $Target.UserPrincipalName }
        $Selection = if ($Keys.Count -eq 0 -and $Paths.Count -eq 0) { 'everything' } else { "$($Keys.Count) item(s) and $($Paths.Count) folder(s)" }
        $Result = if ($Mode -eq 'Apply') {
            "Restoring $Selection from the $Workload backup of $($Source.DisplayName) ($($Job.RunStamp)) to $TargetName"
        } else {
            "Previewing a restore of $Selection from the $Workload backup of $($Source.DisplayName) ($($Job.RunStamp)) to $TargetName. No changes are made."
        }
        Write-LogMessage -headers $Request.Headers -API 'CloudBackupRestore' -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -message $Result -sev Info
        $StatusCode = [HttpStatusCode]::Accepted
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to start the restore: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Request.Headers -API 'CloudBackupRestore' -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $JobId = $null
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result; JobId = $JobId }
        })
}
