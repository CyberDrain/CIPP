function Start-CIPPAuditLogFeedRun {
    <#
    .SYNOPSIS
        Queues one AuditLogFeedV3 task per tenant for the content types whose cursors are due.
    .DESCRIPTION
        Each task carries the tenant's due content types and their AuditLogFeedCursor rows; a content type in backoff
        (NextAttemptUtc in the future) is left out, as is a tenant with none due. A task checkpoints its cursors as it
        works, so the run's post-execution, AuditLogFeedRoundV3, queues this again for every tenant whose task saved a
        checkpoint but did not finish, round after round while they progress.

        Round 0 is the timer's run, named AuditLogFeedV3 so a tick never starts while one is going. Later rounds are named
        AuditLogFeedV3-<guid>, the same run family, so the timer still sees the feed as active. The run is uncapped:
        Craft's background pool bounds how many tasks run at once.

        Returns the number of tasks queued.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Tenants,
        [int]$Round = 0
    )

    $Now = [datetime]::UtcNow
    $CursorTable = Get-CippTable -TableName 'AuditLogFeedCursor'
    $Cursors = @{}
    foreach ($Row in @(Get-CIPPAzDataTableEntity @CursorTable)) {
        $Cursors['{0}|{1}' -f $Row.PartitionKey, $Row.RowKey] = $Row
    }
    $CycleId = $Now.ToString('yyyyMMddHHmmss')

    $Batch = foreach ($Tenant in $Tenants) {
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
            [pscustomobject]@{
                FunctionName = 'AuditLogFeedV3'
                CycleId      = $CycleId
                Tenants      = @([pscustomobject]@{ TenantFilter = $Tenant.defaultDomainName; TenantId = $Tenant.customerId; ContentTypes = @($ContentTypes); Cursors = $TenantCursors })
            }
        }
    }
    $Batch = @($Batch)
    if ($Batch.Count -eq 0 -or -not $PSCmdlet.ShouldProcess('AuditLogFeedV3', "Poll the audit log feed for $($Batch.Count) tenant(s), round $Round")) { return 0 }

    $null = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{
            OrchestratorName = if ($Round -eq 0) { 'AuditLogFeedV3' } else { "AuditLogFeedV3-$([guid]::NewGuid())" }
            AllowCollision   = $Round -gt 0
            Batch            = $Batch
            SkipLog          = $true
            Priority         = 3
            PostExecution    = @{ FunctionName = 'AuditLogFeedRoundV3'; Parameters = @{ RoundStartUtc = $Now.ToString('o'); Round = $Round } }
        })
    $Batch.Count
}
