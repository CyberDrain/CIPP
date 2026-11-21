function Invoke-ListCloudBackupOverview {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackup.Read
    .SYNOPSIS
        Cloud backup overview
    .DESCRIPTION
        Summarises cloud backup: number of policies and destinations, tenants covered by enabled policies, failed runs in the last 24 hours, the latest run for each policy, tenant and workload, and per workload (Exchange, OneDrive, SharePoint, Teams) the policies, tenants, mailboxes, OneDrives, sites, teams or chat users covered, items and bytes backed up by the latest runs, failures in the last 24 hours and the last run. With a tenant, only that tenant's policies and runs are counted.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Optional tenant (default domain or customerId) to summarise
    $TenantFilter = $Request.Query.tenantFilter
    if ($TenantFilter -eq 'AllTenants') { $TenantFilter = $null }

    try {
        $Now = [datetime]::UtcNow
        $AllowedTenants = @(Test-CIPPAccess -Request $Request -TenantList)
        $AllAllowed = $AllowedTenants -contains 'AllTenants'
        $Policies = @(@(Get-CIPPCloudBackupPolicy).Where({ Test-CIPPCloudBackupPolicyScope -Tenants $_.Tenants -AllowedTenants $AllowedTenants }))
        $DestinationCount = @(Get-CIPPCloudBackupDestination).Count

        $SelectedId = $null
        if ($TenantFilter) {
            $SelectedId = (Get-CIPPTenantLookup)["$TenantFilter"].customerId
            if (-not $SelectedId) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body       = @{ Results = "Tenant $TenantFilter was not found" }
                    })
            }
        }

        $TenantList = @(Get-Tenants)
        $Covered = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $Policies = @(foreach ($Policy in $Policies) {
                $PolicyTenantIds = @(Get-CIPPCloudBackupPolicyTenantId -Tenants $Policy.Tenants -TenantList $TenantList)
                if ($SelectedId -and $PolicyTenantIds -notcontains $SelectedId) { continue }
                $Policy
                if (-not $Policy.Enabled) { continue }
                foreach ($TenantId in $PolicyTenantIds) {
                    if ($SelectedId -and $TenantId -ne $SelectedId) { continue }
                    if ($AllAllowed -or $AllowedTenants -contains $TenantId) { [void]$Covered.Add($TenantId) }
                }
            })

        $Hours = @{ '4h' = 4; '6h' = 6; '12h' = 12; '1d' = 24 }
        $DayKey = '{0:D19}' -f ([datetime]::MaxValue.Ticks - $Now.AddDays(-1).Ticks)
        $RunsTable = Get-CIPPTable -TableName 'CloudBackupRuns'
        $Latest = [System.Collections.Generic.List[object]]::new()
        $Failures = 0
        $Stats = [ordered]@{}
        foreach ($Name in @('exchange', 'onedrive', 'sharepoint', 'teams')) {
            $Stats[$Name] = [ordered]@{ Workload = $Name; Policies = 0; Tenants = 0; OwnerCount = 0; Items = [int64]0; Bytes = [int64]0; Failures24h = 0; LastRunAt = $null; LastRunStatus = $null }
        }
        foreach ($Policy in $Policies) {
            if ($Policy.Enabled) { foreach ($Name in $Policy.Workloads) { if ($Stats.Contains($Name)) { $Stats[$Name].Policies++ } } }
            $WindowHours = 24
            foreach ($Name in $Policy.Workloads) { $WindowHours = [Math]::Max($WindowHours, 2 * ($Hours["$($Policy.Schedules.$Name)"] ?? 24)) }
            $WindowKey = '{0:D19}' -f ([datetime]::MaxValue.Ticks - $Now.AddHours(-$WindowHours).Ticks)
            $Seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            $Filter = "PartitionKey eq '$($Policy.Id)' and RowKey lt '$WindowKey'"
            if ($SelectedId) { $Filter = "$Filter and TenantId eq '$SelectedId'" }
            $Rows = Get-CIPPAzDataTableEntity @RunsTable -Filter $Filter -Property PartitionKey, RowKey, PolicyName, TenantId, Tenant, Workload, Status, StartedAt, CompletedAt, Owners, OwnersFailed, Items, Bytes
            foreach ($Row in @($Rows | Sort-Object -Property RowKey)) {
                if (-not $AllAllowed -and $AllowedTenants -notcontains $Row.TenantId) { continue }
                $Name = "$($Row.Workload)"
                $Stat = $Stats[$Name]
                if ($Row.Status -eq 'Failed' -and [string]::CompareOrdinal($Row.RowKey, $DayKey) -lt 0) {
                    $Failures++
                    if ($Stat) { $Stat.Failures24h++ }
                }
                if (-not $Seen.Add("$($Row.TenantId)|$Name")) { continue }
                if ($Stat) {
                    $Stat.Tenants++
                    $Stat.OwnerCount += [int]$Row.Owners
                    $Stat.Items += [int64]$Row.Items
                    $Stat.Bytes += [int64]$Row.Bytes
                    if (-not $Stat.LastRunAt -or [string]::CompareOrdinal("$($Row.StartedAt)", "$($Stat.LastRunAt)") -gt 0) {
                        $Stat.LastRunAt = "$($Row.StartedAt)"
                        $Stat.LastRunStatus = "$($Row.Status)"
                    }
                }
                $Latest.Add([pscustomobject]@{
                        PolicyId     = $Policy.Id
                        PolicyName   = $Row.PolicyName ?? $Policy.Name
                        TenantId     = $Row.TenantId
                        Tenant       = $Row.Tenant
                        Workload     = $Name
                        Status       = $Row.Status
                        CompletedAt  = if ($Row.CompletedAt) { "$($Row.CompletedAt)" } else { $null }
                        OwnerCount   = [int]$Row.Owners
                        FailedOwners = [int]$Row.OwnersFailed
                        Items        = [int64]$Row.Items
                        Bytes        = [int64]$Row.Bytes
                    })
            }
        }

        $Body = [pscustomobject]@{
            Policies        = $Policies.Count
            EnabledPolicies = @($Policies.Where({ $_.Enabled })).Count
            Destinations    = $DestinationCount
            TenantsCovered  = $Covered.Count
            Failures24h     = $Failures
            LatestBytes     = [int64](@(foreach ($Run in $Latest) { $Run.Bytes }) | Measure-Object -Sum).Sum
            LatestRuns      = @($Latest)
            Workloads       = @(foreach ($Stat in $Stats.Values) { [pscustomobject]$Stat })
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to load the cloud backup overview: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $Body = @{ Results = "Failed to load the cloud backup overview: $($ErrorMessage.NormalizedError)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
