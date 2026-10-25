function Invoke-ListAuditLogFeedCycles {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Alert.Read
    .SYNOPSIS
        Lists each audit log check (one every 15 minutes) with how long it took and what it read and alerted on.
    .DESCRIPTION
        One row per check, newest first, over the last Hours (default 48, at most 168): when it started and finished,
        TookSeconds, the workers it used and the longest one (each must finish well inside the 10-minute run limit),
        tenants checked, log batches downloaded and failed, records read, records checked against a rule, alerts sent
        and of those the repeated activity (threshold) alerts. Instance-wide, so it needs access to all tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
    if ($AllowedTenants -notcontains 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Forbidden; Body = @{ Results = 'Feed cycles cover every tenant and need access to all tenants.' } })
    }

    # How many hours back to list, 48 by default and at most 168 (cycles are kept for 7 days).
    $Hours = [Math]::Min([Math]::Max(($Request.Query.Hours -as [int]) ?? 48, 1), 168)
    $Since = [datetime]::UtcNow.AddHours(-$Hours)

    try {
        $CycleTable = Get-CippTable -TableName 'AuditLogFeedCycles'
        $Tasks = @(Get-CIPPAzDataTableEntity @CycleTable -Filter "PartitionKey eq 'Feed' and RowKey ge '$($Since.ToString('yyyyMMddHHmm'))'")
        $Cycles = @{}
        foreach ($Task in $Tasks) {
            $Cycles[[string]$Task.CycleId] ??= [System.Collections.Generic.List[object]]::new()
            $Cycles[[string]$Task.CycleId].Add($Task)
        }

        $Results = foreach ($CycleId in $Cycles.Keys) {
            $CycleTasks = $Cycles[$CycleId]
            $Started = ($CycleTasks.StartedUtc | ForEach-Object { ([datetimeoffset]$_).UtcDateTime } | Measure-Object -Minimum).Minimum
            $Finished = ($CycleTasks.FinishedUtc | ForEach-Object { ([datetimeoffset]$_).UtcDateTime } | Measure-Object -Maximum).Maximum
            [pscustomobject]@{
                CycleId                = $CycleId
                StartedDateTime        = $Started
                FinishedDateTime       = $Finished
                TookSeconds            = [Math]::Round(($Finished - $Started).TotalSeconds, 1)
                LongestWorkerSeconds   = [double](($CycleTasks.DurationSeconds | Measure-Object -Maximum).Maximum)
                Workers                = $CycleTasks.Count
                TenantsChecked         = [int](($CycleTasks.Tenants | Measure-Object -Sum).Sum)
                BatchesDownloaded      = [int](($CycleTasks.Blobs | Measure-Object -Sum).Sum)
                BatchesFailed          = [int](($CycleTasks.Failed | Measure-Object -Sum).Sum)
                RecordsRead            = [int](($CycleTasks.Records | Measure-Object -Sum).Sum)
                RecordsChecked         = [int](($CycleTasks.Evaluated | Measure-Object -Sum).Sum)
                AlertsSent             = [int](($CycleTasks.Matched | Measure-Object -Sum).Sum)
                RepeatedActivityAlerts = [int](($CycleTasks.Thresholds | Measure-Object -Sum).Sum)
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        $Body = @($Results | Sort-Object -Property CycleId -Descending)
    } catch {
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $Body = @{ Results = "Could not read the audit log feed cycles: $($_.Exception.Message)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
