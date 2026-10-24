function Start-CIPPAuditLogFeedListRun {
    <#
    .SYNOPSIS
        Queues the AuditLogFeedListV3 run: listing tasks of up to 50 tenants each, fanned out to blob batch runs after.
    .DESCRIPTION
        Each task carries its tenants' due content types and cursor rows; a content type in backoff (NextAttemptUtc in the
        future) is left out. Listing is waiting on Microsoft, so one task lists many tenants at once. The run's
        post-execution, AuditLogFeedFanOutV3, batches every pending AuditLogFeedBlobs row; with no tenant due it runs now,
        so rows left from an earlier round still go out. Returns the number of listing tasks queued.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Tenants)

    $Now = [datetime]::UtcNow
    $CycleId = $Now.ToString('yyyyMMddHHmmss')
    $CursorTable = Get-CippTable -TableName 'AuditLogFeedCursor'
    $Cursors = @{}
    foreach ($Row in @(Get-CIPPAzDataTableEntity @CursorTable)) { $Cursors['{0}|{1}' -f $Row.PartitionKey, $Row.RowKey] = $Row }

    $Due = foreach ($Tenant in $Tenants) {
        $TenantCursors = @{}
        $ContentTypes = foreach ($ContentType in $Tenant.ContentTypes) {
            $Cursor = $Cursors['{0}|{1}' -f $Tenant.defaultDomainName, $ContentType]
            if ($Cursor.NextAttemptUtc -and ([datetimeoffset]$Cursor.NextAttemptUtc).UtcDateTime -gt $Now) { continue }
            if ($Cursor) {
                $TenantCursors[$ContentType] = @{ LastEndUtc = $Cursor.LastEndUtc; ListedThroughUtc = $Cursor.ListedThroughUtc; Attempts = [int]$Cursor.Attempts; LastErrorCode = [string]$Cursor.LastErrorCode }
            }
            $ContentType
        }
        if ($ContentTypes) { [pscustomobject]@{ TenantFilter = $Tenant.defaultDomainName; TenantId = $Tenant.customerId; ContentTypes = @($ContentTypes); Cursors = $TenantCursors } }
    }
    $Due = @($Due)
    if (-not $PSCmdlet.ShouldProcess('AuditLogFeedListV3', "List the audit log feed for $($Due.Count) tenant(s)")) { return 0 }
    if ($Due.Count -eq 0) {
        Push-AuditLogFeedFanOutV3 -Item @{ Parameters = @{ CycleId = $CycleId; CycleStartUtc = $Now.ToString('o'); Run = 0 } }
        return 0
    }
    $Batch = for ($i = 0; $i -lt $Due.Count; $i += 50) {
        [pscustomobject]@{ FunctionName = 'AuditLogFeedListV3'; CycleId = $CycleId; Tenants = @($Due[$i..([Math]::Min($i + 49, $Due.Count - 1))]) }
    }
    $Batch = @($Batch)
    $null = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{
            OrchestratorName = 'AuditLogFeedListV3'
            Batch            = $Batch
            SkipLog          = $true
            Priority         = 3
            PostExecution    = @{ FunctionName = 'AuditLogFeedFanOutV3'; Parameters = @{ CycleId = $CycleId; CycleStartUtc = $Now.ToString('o'); Run = 0 } }
        })
    $Batch.Count
}
