function Invoke-ListCloudBackupPolicies {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackup.Read
    .SYNOPSIS
        List cloud backup policies
    .DESCRIPTION
        Lists cloud backup policies: which tenants and workloads (Exchange mailboxes, OneDrive, SharePoint, Teams) each backs up, the schedule and next run of each workload, exclusions, the destination, how long earlier versions are kept, whether backups are encrypted, the permission status per tenant and the last run. With a tenant, only the policies that back it up. Callers limited to some tenants only see policies that target just those tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Optional policy id to return a single policy
    $Id = $Request.Query.Id
    # Optional tenant (default domain or customerId) to list the policies that back it up
    $TenantFilter = $Request.Query.tenantFilter
    if ($TenantFilter -eq 'AllTenants') { $TenantFilter = $null }
    if ($Id -and -not ($Id -as [guid])) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Id must be a policy id (GUID)' }
            })
    }

    try {
        $AllowedTenants = @(Test-CIPPAccess -Request $Request -TenantList)
        $Policies = @(@(if ($Id) { Get-CIPPCloudBackupPolicy -Id $Id -IncludePermissionStatus } else { Get-CIPPCloudBackupPolicy -IncludePermissionStatus }).Where({ Test-CIPPCloudBackupPolicyScope -Tenants $_.Tenants -AllowedTenants $AllowedTenants }))
        if ($TenantFilter -and -not $Id) {
            $TenantId = (Get-CIPPTenantLookup)["$TenantFilter"].customerId
            if (-not $TenantId) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body       = @{ Results = "Tenant $TenantFilter was not found" }
                    })
            }
            $TenantList = @(Get-Tenants)
            $Policies = @($Policies.Where({ @(Get-CIPPCloudBackupPolicyTenantId -Tenants $_.Tenants -TenantList $TenantList) -contains $TenantId }))
        }
        if ($Id -and $Policies.Count -eq 0) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Results = "Policy $Id was not found" }
                })
        }

        $Destinations = @{}
        foreach ($Destination in @(Get-CIPPCloudBackupDestination)) { $Destinations["$($Destination.RowKey ?? $Destination.Id)"] = $Destination }
        $TenantsById = @{}
        foreach ($Tenant in @(Get-Tenants -IncludeErrors)) { $TenantsById[$Tenant.customerId] = $Tenant }
        $GroupsById = @{}
        if (@($Policies.Tenants).Where({ $_.type -eq 'Group' }, 'First').Count -gt 0) {
            foreach ($Group in @(Get-TenantGroups)) { $GroupsById["$($Group.Id)"] = $Group }
        }
        $RunsTable = Get-CIPPTable -TableName 'CloudBackupRuns'

        $Body = foreach ($Policy in $Policies) {
            $Tenants = foreach ($Entry in $Policy.Tenants) {
                switch ($Entry.type) {
                    'AllTenants' { [pscustomobject]@{ label = 'All Tenants'; value = 'AllTenants'; type = 'Tenant' } }
                    'Tenant' {
                        $Tenant = $TenantsById[$Entry.customerId]
                        if ($Tenant) {
                            [pscustomobject]@{
                                label       = "$($Tenant.displayName) ($($Tenant.defaultDomainName))"
                                value       = $Tenant.defaultDomainName
                                type        = 'Tenant'
                                addedFields = [pscustomobject]@{ defaultDomainName = $Tenant.defaultDomainName; displayName = $Tenant.displayName; customerId = $Tenant.customerId }
                            }
                        } else {
                            [pscustomobject]@{ label = $Entry.customerId; value = $Entry.customerId; type = 'Tenant'; addedFields = [pscustomobject]@{ customerId = $Entry.customerId } }
                        }
                    }
                    'Group' { [pscustomobject]@{ label = $GroupsById[$Entry.id].Name ?? $Entry.id; value = $Entry.id; type = 'Group' } }
                }
            }
            $Tenants = @($Tenants)
            $TenantCount = @($Policy.Tenants.Where({ $_.type -eq 'Tenant' })).Count
            $GroupCount = @($Policy.Tenants.Where({ $_.type -eq 'Group' })).Count
            $TenantSummary = if (@($Policy.Tenants.Where({ $_.type -eq 'AllTenants' })).Count -gt 0) {
                'All tenants'
            } elseif ($Tenants.Count -le 3) {
                ($Tenants.label -join ', ')
            } else {
                @(
                    if ($TenantCount -gt 0) { "$TenantCount $(if ($TenantCount -eq 1) { 'tenant' } else { 'tenants' })" }
                    if ($GroupCount -gt 0) { "$GroupCount $(if ($GroupCount -eq 1) { 'group' } else { 'groups' })" }
                ) -join ', '
            }

            $LastRun = @(Get-CIPPAzDataTableEntity @RunsTable -Filter "PartitionKey eq '$($Policy.Id)'" -First 1 -Property PartitionKey, RowKey, Status, StartedAt)[0]
            $Destination = $Destinations[$Policy.DestinationId]
            $PermissionStatus = [ordered]@{}
            foreach ($TenantId in $Policy.PermissionStatus.Keys) {
                $Status = $Policy.PermissionStatus[$TenantId]
                $PermissionStatus[$TenantId] = [pscustomobject]@{
                    Tenant    = $TenantsById[$TenantId].defaultDomainName ?? $TenantId
                    Status    = $Status.Status
                    Message   = $Status.Message
                    CheckedAt = $Status.CheckedAt
                }
            }

            [pscustomobject]@{
                Id               = $Policy.Id
                Name             = $Policy.Name
                Enabled          = $Policy.Enabled
                DestinationId    = $Policy.DestinationId
                DestinationName  = $Destination.Name
                Provider         = $Destination.Provider
                Tenants          = $Tenants
                TenantSummary    = $TenantSummary
                Workloads        = @($Policy.Workloads)
                Schedules        = $Policy.Schedules
                NextRuns         = $Policy.NextRuns
                Exclusions       = $Policy.Exclusions
                PermissionStatus = [pscustomobject]$PermissionStatus
                RetentionDays    = $Policy.RetentionDays
                Encryption       = $Policy.Encryption
                CurrentKeyId     = if ($Policy.CurrentKeyId) { $Policy.CurrentKeyId } else { $null }
                KeyCount         = @($Policy.KeyIds).Count
                LastRunAt        = if ($LastRun) { "$($LastRun.StartedAt)" } else { $null }
                LastRunStatus    = if ($LastRun) { $LastRun.Status } else { $null }
                LastPrunedAt     = $Policy.LastPrunedAt
                PruneStatus      = $Policy.PruneStatus
                PruneError       = $Policy.PruneError
                PruneSkipped     = $Policy.PruneSkipped
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to list cloud backup policies: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = @{ Results = "Failed to list cloud backup policies: $($ErrorMessage.NormalizedError)" }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Body)
        })
}
