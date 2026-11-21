function Invoke-ListCloudBackupJobs {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackup.Read
    .SYNOPSIS
        List cloud backup compare, restore, export and storage provisioning jobs
    .DESCRIPTION
        Lists the newest 200 compare, restore preview, restore, export and storage provisioning jobs of the last 30 days with their status, tenants, who started them and a summary of the results. Exports show whether their zip can still be downloaded. With Id, returns that job including its result items; restore and restore preview results are paged with ResultSkip and ResultTake (at most 1000), with ResultTotal the number of results. With a tenant, only the jobs that read from or wrote to it. Callers limited to some tenants only see jobs for those tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Optional job id to return one job with its results
    $Id = $Request.Query.Id
    # Optional tenant (default domain or customerId) to list the jobs of
    $TenantFilter = $Request.Query.tenantFilter
    if ($TenantFilter -eq 'AllTenants') { $TenantFilter = $null }
    # Restore results to skip and return with Id
    $ResultSkip = if ("$($Request.Query.ResultSkip)") { "$($Request.Query.ResultSkip)" -as [int] } else { 0 }
    $ResultTake = if ("$($Request.Query.ResultTake)") { "$($Request.Query.ResultTake)" -as [int] } else { 500 }

    if ($Id -and -not ($Id -as [guid])) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Id must be a job id (GUID)' }
            })
    }
    if ($null -eq $ResultSkip -or $null -eq $ResultTake -or $ResultSkip -lt 0 -or $ResultTake -lt 1 -or $ResultTake -gt 1000) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'ResultSkip must be 0 or more and ResultTake from 1 to 1000' }
            })
    }

    try {
        $AllowedTenants = @(Test-CIPPAccess -Request $Request -TenantList)
        $AllAllowed = $AllowedTenants -contains 'AllTenants'
        $Lookup = Get-CIPPTenantLookup
        $Table = Get-CIPPTable -TableName 'CloudBackupJobs'
        $Now = [datetime]::UtcNow.ToString('o')

        $Filter = "PartitionKey eq 'CloudBackupJob'"
        if ($Id) { $Filter = "$Filter and RowKey eq '$([guid]$Id)'" }
        if ($TenantFilter -and -not $Id) {
            $SelectedId = $Lookup["$TenantFilter"].customerId
            if (-not $SelectedId) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body       = @{ Results = "Tenant $TenantFilter was not found" }
                    })
            }
            $Filter = "$Filter and (SourceTenantId eq '$SelectedId' or TargetTenantId eq '$SelectedId')"
        }
        $Found = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)
        $Rows = [System.Collections.Generic.List[object]]::new()
        foreach ($Row in $Found) {
            if ($AllAllowed -or ($AllowedTenants -contains $Row.SourceTenantId -and $AllowedTenants -contains $Row.TargetTenantId)) { $Rows.Add($Row) }
        }

        if ($Id -and $Found.Count -eq 0) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Results = "Job $Id was not found" }
                })
        }
        if ($Id -and $Rows.Count -eq 0) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = @{ Results = 'You do not have access to the tenants of this job' }
                })
        }

        $Selected = if ($Id) { @($Rows) } else { @($Rows | Sort-Object -Property CreatedAt -Descending | Select-Object -First 200) }
        $Jobs = foreach ($Row in $Selected) {
            $Job = [pscustomobject]@{
                Id             = $Row.RowKey
                Type           = $Row.Type
                Status         = $Row.Status
                RunId          = $Row.RunId
                CompareToRunId = if ($Row.CompareToRunId) { $Row.CompareToRunId } else { $null }
                SourceTenantId = $Row.SourceTenantId
                SourceTenant   = $Lookup["$($Row.SourceTenantId)"].defaultDomainName ?? $Row.SourceTenant
                TargetTenantId = $Row.TargetTenantId
                TargetTenant   = $Lookup["$($Row.TargetTenantId)"].defaultDomainName ?? $Row.TargetTenant
                Parameters     = if ($Row.Parameters) { [CIPP.CippJson]::ConvertFromJson([string]$Row.Parameters) } else { $null }
                PreviewJobId   = if ($Row.PreviewJobId) { $Row.PreviewJobId } else { $null }
                RequestedBy    = $Row.RequestedBy
                CreatedAt      = if ($Row.CreatedAt) { "$($Row.CreatedAt)" } else { $null }
                StartedAt      = if ($Row.StartedAt) { "$($Row.StartedAt)" } else { $null }
                CompletedAt    = if ($Row.CompletedAt) { "$($Row.CompletedAt)" } else { $null }
                Summary        = if ($Row.Summary) { [CIPP.CippJson]::ConvertFromJson([string]$Row.Summary) } else { $null }
                Steps          = if ($Row.Steps) { @([CIPP.CippJson]::ConvertFromJson([string]$Row.Steps)) } else { $null }
                Error          = if ($Row.Error) { $Row.Error } else { $null }
            }
            if ($Row.Type -in @('Restore', 'RestorePreview', 'Export')) {
                $DownloadAvailable = $Row.Type -eq 'Export' -and $Row.Status -eq 'Completed' -and [bool]$Row.ExportKey -and -not $Row.ExportRemovedAt -and [string]::CompareOrdinal("$($Row.ExpiresAt)", $Now) -gt 0
                $Job.PSObject.Properties.Add([psnoteproperty]::new('PolicyId', $Row.PolicyId))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('Workload', $Row.Workload))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('SourceOwnerId', $Row.SourceOwnerId))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('SourceOwnerName', $Row.SourceOwnerName))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('SourceOwner', $(if ($Row.SourceOwnerName) { $Row.SourceOwnerName } else { $Row.SourceOwnerId })))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('TargetOwner', $(if ($Row.TargetOwnerType -eq 'Site') { $(if ($Row.SourceOwnerName) { $Row.SourceOwnerName } else { $Row.TargetOwnerId }) } elseif ($Row.TargetUserPrincipalName) { $Row.TargetUserPrincipalName } elseif ($Row.TargetOwnerId) { $Row.TargetOwnerId } else { $null })))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('SourceRemoved', "$($Row.SourceRemoved)" -eq 'True'))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('TargetOwnerId', $(if ($Row.TargetOwnerId) { $Row.TargetOwnerId } else { $null })))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('TargetUserPrincipalName', $(if ($Row.TargetUserPrincipalName) { $Row.TargetUserPrincipalName } else { $null })))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('RunStamp', $Row.RunStamp))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('Location', $(if ($Row.Location) { $Row.Location } else { $null })))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('RestoredFolderName', $(if ($Row.RestoredFolderName) { $Row.RestoredFolderName } else { $null })))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('ConflictAction', $(if ($Row.ConflictAction) { $Row.ConflictAction } else { $null })))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('ItemCount', [int]($Row.ItemCount -as [int])))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('AppliedJobId', $(if ($Row.AppliedJobId) { $Row.AppliedJobId } else { $null })))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('DownloadAvailable', $DownloadAvailable))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('ExpiresAt', $(if ($Row.ExpiresAt) { "$($Row.ExpiresAt)" } else { $null })))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('ExportBytes', [int64]($Row.ExportBytes -as [int64])))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('Warnings', @(if ($Row.Warnings) { [CIPP.CippJson]::ConvertFromJson([string]$Row.Warnings) })))
            }
            if ($Id -and $Row.Type -in @('Restore', 'RestorePreview')) {
                $ResultTotal = [int]($Row.ResultCount -as [int])
                $Result = [System.Collections.Generic.List[object]]::new()
                if ($ResultSkip -lt $ResultTotal) {
                    $Policy = Get-CIPPCloudBackupPolicy -Id $Row.PolicyId
                    $Destination = if ($Policy) { Get-CIPPCloudBackupDestination -Id $Policy.DestinationId -IncludeSecret }
                    if ($Destination) {
                        $Suffix = if ($Row.DataKeyId) { '.enc' } else { '' }
                        $Page = [int][Math]::Floor($ResultSkip / 1000)
                        $Position = $Page * 1000
                        while ($Result.Count -lt $ResultTake -and $Position -lt $ResultTotal) {
                            $Rows = Get-CIPPCloudBackupJsonl -Destination $Destination -Key ('{0}/jobs/{1}/results/{2:D5}.jsonl.gz{3}' -f $Row.PolicyId, $Row.RowKey, $Page, $Suffix)
                            if ($null -eq $Rows) { break }
                            foreach ($ResultItem in $Rows) {
                                if ($Position -ge $ResultSkip -and $Result.Count -lt $ResultTake) { $Result.Add($ResultItem) }
                                $Position++
                            }
                            $Page++
                        }
                    }
                }
                $Job.PSObject.Properties.Add([psnoteproperty]::new('Result', $Result.ToArray()))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('ResultTotal', $ResultTotal))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('ResultSkip', $ResultSkip))
                $Job.PSObject.Properties.Add([psnoteproperty]::new('ResultTake', $ResultTake))
            } elseif ($Id -and $Row.Type -eq 'Export') {
                $Job.PSObject.Properties.Add([psnoteproperty]::new('Result', @()))
            } elseif ($Id) {
                $ResultRow = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CloudBackupJobResult' and RowKey eq '$($Row.RowKey)'")[0]
                $Result = @(if ($ResultRow.Result) { [CIPP.CippJson]::ConvertFromJson([string]$ResultRow.Result) })
                if ($Row.Type -eq 'Provision') { $Result = $Result[0] }
                $Job.PSObject.Properties.Add([psnoteproperty]::new('Result', $Result))
            }
            $Job
        }
        $Body = @($Jobs)
        if ($Id) { $Body = $Body[0] }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to list cloud backup jobs: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = @{ Results = "Failed to list cloud backup jobs: $($ErrorMessage.NormalizedError)" }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
