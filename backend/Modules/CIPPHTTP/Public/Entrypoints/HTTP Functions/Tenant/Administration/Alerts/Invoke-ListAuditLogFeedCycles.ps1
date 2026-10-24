function Invoke-ListAuditLogFeedCycles {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Alert.Read
    .SYNOPSIS
        Lists the audit log feed's polling rounds with their times and counts.
    .DESCRIPTION
        One row per feed round, newest first, over the last Hours (default 48, at most 168): its tasks and tenants,
        records read, evaluated and matched by a rule (the alerts sent, since each task sends its own), failures and
        parked feeds, and the round's start, end and duration. Instance-wide, so it needs access to all tenants.
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
                CycleId     = $CycleId
                StartedUtc  = $Started
                FinishedUtc = $Finished
                Seconds     = [Math]::Round(($Finished - $Started).TotalSeconds, 1)
                Tasks       = $CycleTasks.Count
                Tenants     = [int](($CycleTasks.Tenants | Measure-Object -Sum).Sum)
                Feeds       = [int](($CycleTasks.Feeds | Measure-Object -Sum).Sum)
                Failed      = [int](($CycleTasks.Failed | Measure-Object -Sum).Sum)
                Parked      = [int](($CycleTasks.Parked | Measure-Object -Sum).Sum)
                Blobs       = [int](($CycleTasks.Blobs | Measure-Object -Sum).Sum)
                Records     = [int](($CycleTasks.Records | Measure-Object -Sum).Sum)
                Evaluated   = [int](($CycleTasks.Evaluated | Measure-Object -Sum).Sum)
                Matched     = [int](($CycleTasks.Matched | Measure-Object -Sum).Sum)
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
