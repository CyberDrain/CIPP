function Start-AuditLogFeedV3 {
    <#
    .SYNOPSIS
        Timer entrypoint for audit log alerting: the Management Activity API feed, plus Graph audit searches already
        created.
    .DESCRIPTION
        Each tick runs three independent stages:
          1. Sweep: feed windows still Storing, Downloaded or Processing after the run that wrote them has gone are queued
             again through AuditLogFeedProcessV3, as an AuditLogSweepV3 run: older than 5 minutes with no feed,
             processing or sweep run active, or Processing for more than 2 hours whatever is running. It runs before
             the feed stage, which would otherwise always look active.
          2. Feed: skipped while an AuditLogProcessV3 run is still going, so polling never competes with processing for
             background slots; the cursors carry the skipped range to the next tick. Otherwise the in-scope tenants are
             fanned out in chunks of -TenantsPerTask as AuditLogFeedV3 tasks, each carrying the tenant's content types
             and their AuditLogFeedCursor rows. Content types in backoff (NextAttemptUtc in the future) are left out, as
             are tenants with none due. The run's post-execution, AuditLogFeedProcessV3, processes what the tasks stored.
             Every task carries the tick's CycleId, which its AuditLogFeedCycles row and feed windows are recorded under.
          3. Graph searches: Start-AuditLogIngestionV2 downloads and processes searches that already exist, which are
             manual searches and scheduled windows created before the feed. No scheduled searches are created.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([int]$TenantsPerTask = 25)

    $Now = [datetime]::UtcNow

    $Bridge = 'Craft.Services.OrchestratorBridge' -as [type]
    try {
        $RunsActive = $Bridge -and @('AuditLogFeedV3', 'AuditLogProcessV3', 'AuditLogSweepV3').Where({ [Craft.Services.OrchestratorBridge]::IsRunActive($_) }, 'First').Count -gt 0
        $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
        $Missed = foreach ($Row in @(Get-CIPPAzDataTableEntity @Ledger -Filter "Type eq 'Feed' and (State eq 'Storing' or State eq 'Downloaded' or State eq 'Processing')" -Property @('PartitionKey', 'RowKey', 'State', 'SearchId', 'CandidateCount', 'Timestamp'))) {
            $Age = $Now - $Row.Timestamp.UtcDateTime
            if ((-not $RunsActive -and $Age.TotalMinutes -gt 5) -or ($Row.State -eq 'Processing' -and $Age.TotalHours -gt 2)) {
                [pscustomobject]@{ TenantFilter = [string]$Row.PartitionKey; SearchId = [string]$Row.SearchId; WindowRowKey = [string]$Row.RowKey; RecordCount = [int]$Row.CandidateCount }
            }
        }
        $Missed = @($Missed)
        if ($Missed.Count -gt 0 -and $PSCmdlet.ShouldProcess('Start-AuditLogFeedV3', "Process $($Missed.Count) feed window(s) whose run is gone")) {
            Write-Information "AuditLogFeedV3: $($Missed.Count) feed window(s) whose run is gone"
            Push-AuditLogFeedProcessV3 -Item ([pscustomobject]@{ Results = $Missed; Parameters = @{ RunName = 'AuditLogSweepV3' } })
        }
    } catch {
        Write-LogMessage -API 'AuditLogFeedV3' -message 'Audit log feed sweep failed' -sev Error -LogData (Get-CippException -Exception $_)
    }

    $ProcessingActive = $Bridge -and [Craft.Services.OrchestratorBridge]::IsRunActive('AuditLogProcessV3')
    if ($ProcessingActive) {
        Write-Information 'AuditLogFeedV3: feed skipped, audit log processing is still running'
    } else {
        try {
            $CursorTable = Get-CippTable -TableName 'AuditLogFeedCursor'
            $Cursors = @{}
            foreach ($Row in @(Get-CIPPAzDataTableEntity @CursorTable)) {
                $Cursors['{0}|{1}' -f $Row.PartitionKey, $Row.RowKey] = $Row
            }

            $Due = foreach ($Tenant in @(Get-CIPPAuditLogTenantScope)) {
                $TenantCursors = @{}
                $ContentTypes = foreach ($ContentType in $Tenant.ContentTypes) {
                    $Cursor = $Cursors['{0}|{1}' -f $Tenant.defaultDomainName, $ContentType]
                    if ($Cursor.NextAttemptUtc -and ([datetimeoffset]$Cursor.NextAttemptUtc).UtcDateTime -gt $Now) { continue }
                    if ($Cursor) {
                        $TenantCursors[$ContentType] = @{ LastEndUtc = $Cursor.LastEndUtc; Attempts = [int]$Cursor.Attempts; LastErrorCode = [string]$Cursor.LastErrorCode }
                    }
                    $ContentType
                }
                if ($ContentTypes) {
                    [pscustomobject]@{ TenantFilter = $Tenant.defaultDomainName; TenantId = $Tenant.customerId; ContentTypes = @($ContentTypes); Cursors = $TenantCursors }
                }
            }
            $Due = @($Due)
            if ($Due.Count -gt 0) {
                $Batch = for ($i = 0; $i -lt $Due.Count; $i += $TenantsPerTask) {
                    [pscustomobject]@{ FunctionName = 'AuditLogFeedV3'; CycleId = $Now.ToString('yyyyMMddHHmm'); Tenants = @($Due[$i..([Math]::Min($i + $TenantsPerTask - 1, $Due.Count - 1))]) }
                }
                Write-Information "AuditLogFeedV3: $($Due.Count) tenant(s) in $(@($Batch).Count) task(s)"
                if ($PSCmdlet.ShouldProcess('Start-AuditLogFeedV3', 'Poll the audit log feed')) {
                    Start-CIPPOrchestrator -InputObject ([pscustomobject]@{
                            OrchestratorName = 'AuditLogFeedV3'
                            AllowCollision   = $false
                            Batch            = @($Batch)
                            SkipLog          = $true
                            Priority         = 3
                            PostExecution    = @{ FunctionName = 'AuditLogFeedProcessV3'; Parameters = @{} }
                        })
                }
            } else {
                Write-Information 'AuditLogFeedV3: no tenants due'
            }
        } catch {
            Write-LogMessage -API 'AuditLogFeedV3' -message 'Audit log feed stage failed' -sev Error -LogData (Get-CippException -Exception $_)
        }
    }

    try {
        Start-AuditLogIngestionV2
    } catch {
        Write-LogMessage -API 'AuditLogFeedV3' -message 'Audit log search ingestion failed' -sev Error -LogData (Get-CippException -Exception $_)
    }
}
