function Invoke-ListAuditLogFeedCycles {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Alert.Read
    .SYNOPSIS
        Lists the audit log feed's polling cycles with their feed and processing times.
    .DESCRIPTION
        One row per timer tick that polled the feed, newest first, over the last Hours (default 48, at most 168): the
        feed tasks' tenants, records read, evaluated and stored, failures and parked feeds, the feed run's start, end
        and duration, and from the feed windows the run stored, how many were processed, the alerts they matched and
        how long processing took after the feed run ended. Instance-wide, so it needs access to all tenants.
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
        $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
        $SinceIso = ConvertTo-CIPPODataFilterValue -Value $Since.ToString('yyyy-MM-ddTHH:mm:ssZ') -Type Date
        $Windows = @{}
        foreach ($Row in @(Get-CIPPAzDataTableEntity @Ledger -Filter "Type eq 'Feed' and CreatedUtc ge datetime'$SinceIso'" -Property @('PartitionKey', 'RowKey', 'CycleId', 'State', 'MatchedCount', 'ProcessedUtc'))) {
            if (-not $Row.CycleId) { continue }
            $Windows[[string]$Row.CycleId] ??= [System.Collections.Generic.List[object]]::new()
            $Windows[[string]$Row.CycleId].Add($Row)
        }

        $Cycles = @{}
        foreach ($Task in $Tasks) {
            $Cycles[[string]$Task.CycleId] ??= [System.Collections.Generic.List[object]]::new()
            $Cycles[[string]$Task.CycleId].Add($Task)
        }

        $Results = foreach ($CycleId in $Cycles.Keys) {
            $CycleTasks = $Cycles[$CycleId]
            $Started = ($CycleTasks.StartedUtc | ForEach-Object { ([datetimeoffset]$_).UtcDateTime } | Measure-Object -Minimum).Minimum
            $Finished = ($CycleTasks.FinishedUtc | ForEach-Object { ([datetimeoffset]$_).UtcDateTime } | Measure-Object -Maximum).Maximum
            $CycleWindows = @($Windows[$CycleId])
            $Processed = @($CycleWindows.Where({ $_.State -eq 'Processed' }))
            $ProcessedUtc = if ($CycleWindows.Count -gt 0 -and $Processed.Count -eq $CycleWindows.Count) {
                ($Processed.ProcessedUtc | ForEach-Object { ([datetimeoffset]$_).UtcDateTime } | Measure-Object -Maximum).Maximum
            }
            [pscustomobject]@{
                CycleId           = $CycleId
                StartedUtc        = $Started
                FeedFinishedUtc   = $Finished
                FeedSeconds       = [Math]::Round(($Finished - $Started).TotalSeconds, 1)
                Tasks             = $CycleTasks.Count
                Tenants           = [int](($CycleTasks.Tenants | Measure-Object -Sum).Sum)
                Feeds             = [int](($CycleTasks.Feeds | Measure-Object -Sum).Sum)
                Failed            = [int](($CycleTasks.Failed | Measure-Object -Sum).Sum)
                Parked            = [int](($CycleTasks.Parked | Measure-Object -Sum).Sum)
                Blobs             = [int](($CycleTasks.Blobs | Measure-Object -Sum).Sum)
                Records           = [int](($CycleTasks.Records | Measure-Object -Sum).Sum)
                Evaluated         = [int](($CycleTasks.Evaluated | Measure-Object -Sum).Sum)
                Stored            = [int](($CycleTasks.Stored | Measure-Object -Sum).Sum)
                Windows           = $CycleWindows.Count
                WindowsProcessed  = $Processed.Count
                Alerts            = [int](($Processed.MatchedCount | Measure-Object -Sum).Sum)
                ProcessedUtc      = $ProcessedUtc
                ProcessingSeconds = if ($ProcessedUtc) { [Math]::Round([Math]::Max(($ProcessedUtc - $Finished).TotalSeconds, 0), 1) }
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
