function Invoke-ListCloudBackupRuns {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackup.Read
    .SYNOPSIS
        List cloud backup runs
    .DESCRIPTION
        Lists cloud backup run history, newest first (at most 1000 runs): one run per policy, tenant and workload with its status, when it ran, how long it took, how many mailboxes, OneDrives, sites, teams or chat users it covered and how many failed, how many items and bytes were backed up or deleted, warnings, and where the backup is stored. Filter by policy, tenant or workload. Callers limited to some tenants only see runs for those tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $MaxRuns = 1000
    # Optional policy id to list the runs of one policy
    $PolicyId = $Request.Query.PolicyId
    # Optional tenant (default domain or customerId) to list the runs of one tenant
    $TenantFilter = $Request.Query.tenantFilter
    # Optional workload to list the runs of: exchange, onedrive, sharepoint or teams
    $Workload = "$($Request.Query.Workload)".ToLowerInvariant()

    if ($PolicyId -and -not ($PolicyId -as [guid])) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'PolicyId must be a policy id (GUID)' }
            })
    }
    if ($Workload -and $Workload -notin @('exchange', 'onedrive', 'sharepoint', 'teams')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Workload must be exchange, onedrive, sharepoint or teams' }
            })
    }
    if ($TenantFilter -eq 'AllTenants') { $TenantFilter = $null }

    try {
        $AllowedTenants = @(Test-CIPPAccess -Request $Request -TenantList)
        $AllAllowed = $AllowedTenants -contains 'AllTenants'

        $TenantId = $null
        if ($TenantFilter) {
            $TenantId = (Get-CIPPTenantLookup)["$TenantFilter"].customerId
            if (-not $TenantId) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body       = @{ Results = "Tenant $TenantFilter was not found" }
                    })
            }
        }

        $PolicyIds = if ($PolicyId) { @("$([guid]$PolicyId)") } else { @(@(Get-CIPPCloudBackupPolicy).Id) }
        $RunsTable = Get-CIPPTable -TableName 'CloudBackupRuns'
        $Rows = [System.Collections.Generic.List[object]]::new()
        foreach ($Id in $PolicyIds) {
            $Filter = "PartitionKey eq '$Id'"
            if ($TenantId) { $Filter = "$Filter and TenantId eq '$TenantId'" }
            if ($Workload) { $Filter = "$Filter and Workload eq '$Workload'" }
            foreach ($Row in @(Get-CIPPAzDataTableEntity @RunsTable -Filter $Filter -First $MaxRuns)) {
                if ($AllAllowed -or $AllowedTenants -contains $Row.TenantId) { $Rows.Add($Row) }
            }
        }

        $Body = foreach ($Row in @($Rows | Sort-Object -Property RowKey | Select-Object -First $MaxRuns)) {
            $Started = [datetimeoffset]::MinValue
            $Completed = [datetimeoffset]::MinValue
            $Duration = if ([datetimeoffset]::TryParse("$($Row.StartedAt)", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Started) -and
                [datetimeoffset]::TryParse("$($Row.CompletedAt)", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$Completed)) {
                [int][Math]::Round(($Completed - $Started).TotalSeconds)
            } else { $null }
            [pscustomobject]@{
                Id              = "$($Row.PartitionKey)_$($Row.RowKey)"
                PolicyId        = $Row.PolicyId
                PolicyName      = $Row.PolicyName
                TenantId        = $Row.TenantId
                Tenant          = $Row.Tenant
                Workload        = $Row.Workload
                Status          = $Row.Status
                StartedAt       = if ($Row.StartedAt) { "$($Row.StartedAt)" } else { $null }
                CompletedAt     = if ($Row.CompletedAt) { "$($Row.CompletedAt)" } else { $null }
                DurationSeconds = $Duration
                OwnerCount      = [int]$Row.Owners
                SucceededOwners = [int]$Row.OwnersSucceeded
                FailedOwners    = [int]$Row.OwnersFailed
                Items           = [int64]$Row.Items
                Bytes           = [int64]$Row.Bytes
                Deleted         = [int64]$Row.Deleted
                Warnings        = @(if ($Row.Warnings) { [CIPP.CippJson]::ConvertFromJson([string]$Row.Warnings) })
                Location        = $Row.Location
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to list cloud backup runs: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = @{ Results = "Failed to list cloud backup runs: $($ErrorMessage.NormalizedError)" }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Body)
        })
}
