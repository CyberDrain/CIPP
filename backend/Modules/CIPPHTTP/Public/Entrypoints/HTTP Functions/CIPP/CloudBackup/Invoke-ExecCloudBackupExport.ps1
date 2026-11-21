function Invoke-ExecCloudBackupExport {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackupRestore.ReadWrite
    .SYNOPSIS
        Export backed-up items to a zip file
    .DESCRIPTION
        Queues an export of items, folders or a whole mailbox, OneDrive, SharePoint site or Teams backup at a point in time into a zip file kept in the policy's destination for 7 days, and returns its JobId. Poll ListCloudBackupJobs with the JobId; when DownloadAvailable is true, download the zip with ExecCloudBackupDownload?JobId=.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $PolicyId = "$($Request.Body.PolicyId)"
    # Tenant of the backup (customerId or default domain)
    $TenantId = "$($Request.Body.TenantId.value ?? $Request.Body.TenantId)"
    # exchange, onedrive, sharepoint or teams
    $Workload = "$($Request.Body.Workload.value ?? $Request.Body.Workload)".ToLowerInvariant()
    # Owner id as returned by ListCloudBackupOwners
    $OwnerId = "$($Request.Body.OwnerId.value ?? $Request.Body.OwnerId)"
    # Recovery point (RunStamp) or date and time; the newest backup when empty
    $AsOf = "$($Request.Body.AsOf)".Trim()
    # Item keys to export
    $Keys = @(foreach ($Key in @($Request.Body.Keys)) { if ($null -ne $Key -and "$Key" -ne '') { "$Key" } })
    # Folder paths to export, including everything below them; with no Keys and no Paths the whole owner is exported
    $Paths = @(foreach ($Path in @($Request.Body.Paths)) { if ($null -ne $Path) { "$Path".Trim('/') } })

    if (-not ($PolicyId -as [guid])) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'PolicyId must be a policy id (GUID)' } })
    }
    if (-not $TenantId -or $TenantId -eq 'AllTenants' -or $TenantId -like 'group:*') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'TenantId must be a single tenant' } })
    }
    if ($Workload -notin @('exchange', 'onedrive', 'sharepoint', 'teams')) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Workload must be exchange, onedrive, sharepoint or teams' } })
    }
    if (-not $OwnerId) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'OwnerId is required' } })
    }
    if ($Keys.Count -gt 10000 -or $Paths.Count -gt 1000) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Select at most 10000 items and 1000 folders, or export the parent folder instead' } })
    }
    $ParsedAsOf = [datetimeoffset]::MinValue
    if ($AsOf -and -not [datetimeoffset]::TryParseExact($AsOf, 'yyyyMMddTHHmmssZ', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$ParsedAsOf) -and
        -not [datetimeoffset]::TryParse($AsOf, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$ParsedAsOf)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'AsOf must be a recovery point or a date and time' } })
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

        $Source = Resolve-CIPPCloudBackupJobSource -PolicyId $PolicyId -TenantId $Tenant.customerId -Workload $Workload -OwnerId $OwnerId -AsOf $AsOf
        $Policy = $Source.Policy
        $Parameters = [ordered]@{
            PolicyId = "$($Policy.Id)"
            TenantId = "$($Tenant.customerId)"
            Workload = $Workload
            OwnerId  = $OwnerId
            AsOf     = $AsOf
            Keys     = [string[]]@([System.Collections.Generic.SortedSet[string]]::new([string[]]@($Keys), [System.StringComparer]::Ordinal))
            Paths    = [string[]]@([System.Collections.Generic.SortedSet[string]]::new([string[]]@($Paths), [System.StringComparer]::Ordinal))
        }
        $Principal = try { [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json } catch { $null }
        $RequestedBy = if ($Request.Headers.'x-ms-client-principal-idp' -eq 'aad') { $Request.Headers.'x-ms-client-principal-name' } else { $Principal.userDetails ?? $Request.Headers.'x-ms-client-principal-name' ?? 'CIPP' }

        $JobId = [guid]::NewGuid().ToString()
        $Now = [datetime]::UtcNow.ToString('o')
        $JobsTable = Get-CIPPTable -TableName 'CloudBackupJobs'
        Add-CIPPAzDataTableEntity @JobsTable -Entity @{
            PartitionKey    = 'CloudBackupJob'
            RowKey          = $JobId
            Type            = 'Export'
            Status          = 'Queued'
            RunId           = ''
            CompareToRunId  = ''
            PolicyId        = "$($Policy.Id)"
            Workload        = $Workload
            SourceTenantId  = "$($Tenant.customerId)"
            SourceTenant    = "$($Tenant.defaultDomainName)"
            TargetTenantId  = "$($Tenant.customerId)"
            TargetTenant    = "$($Tenant.defaultDomainName)"
            SourceOwnerId   = $OwnerId
            SourceOwnerType = $Source.OwnerType
            SourceOwnerName = $Source.DisplayName
            SourceRemoved   = $Source.Removed
            AsOf            = $AsOf
            RunStamp        = $Source.RunStamp
            DataKeyId       = if ($Policy.Encryption -and $Policy.CurrentKeyId) { "$($Policy.CurrentKeyId)" } else { '' }
            ManifestJobId   = $JobId
            ManifestReady   = $false
            ItemCount       = 0
            Parameters      = [CIPP.CippJson]::ToJson($Parameters, 5) ?? (ConvertTo-Json -InputObject $Parameters -Depth 5 -Compress)
            ParametersHash  = ''
            PreviewJobId    = ''
            RequestedBy     = "$RequestedBy"
            CreatedAt       = $Now
            UpdatedAt       = $Now
            StartedAt       = ''
            CompletedAt     = ''
            Attempts        = 0
            ExportKey       = ''
            ExportBytes     = 0
            ExpiresAt       = ''
            ExportRemovedAt = ''
            Summary         = ''
            Error           = ''
        } -Force

        $Queued = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{
                Batch            = @([pscustomobject]@{ FunctionName = 'CloudBackupExport'; JobId = $JobId; QueueName = $Tenant.defaultDomainName })
                OrchestratorName = "CloudBackupExport_$JobId"
                SkipLog          = $true
            })
        if (-not $Queued) {
            Add-CIPPAzDataTableEntity @JobsTable -Entity @{ PartitionKey = 'CloudBackupJob'; RowKey = $JobId; Status = 'Failed'; Error = 'The export could not be queued'; CompletedAt = [datetime]::UtcNow.ToString('o') } -OperationType 'UpsertMerge'
            throw 'The export could not be queued'
        }

        $Selection = if ($Keys.Count -eq 0 -and $Paths.Count -eq 0) { 'everything' } else { "$($Keys.Count) item(s) and $($Paths.Count) folder(s)" }
        $Result = "Exporting $Selection from the $Workload backup of $($Source.DisplayName) ($($Source.RunStamp)). The download is kept for 7 days."
        Write-LogMessage -headers $Request.Headers -API 'CloudBackupRestore' -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -message $Result -sev Info
        $StatusCode = [HttpStatusCode]::Accepted
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to start the export: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Request.Headers -API 'CloudBackupRestore' -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $JobId = $null
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result; JobId = $JobId }
        })
}
