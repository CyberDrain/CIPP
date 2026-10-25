function Invoke-ListAuditLogFeedStatus {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Alert.Read
    .SYNOPSIS
        Lists how far CIPP has collected each tenant's audit logs for alerting, with any problem and what to do about it.
    .DESCRIPTION
        One row per tenant in audit log alert scope and log (Entra ID, Exchange, SharePoint and OneDrive, General), from
        its AuditLogFeedCursor row. Status is Up to date, Delayed (more than an hour behind), Error retrying, Unavailable
        (audit logging off, or no licence with an audit log; checked once a day) or Waiting to start. CheckedUpToDateTime
        is how far alerts are complete, CollectedUpToDateTime how far log batches are listed, DelayMinutes how far
        behind now. Problem, ProblemDetail and WhatToDo explain the current error in plain language; ErrorCode and
        ErrorDetail keep the raw error. BatchesWaiting and BatchesFailing count the listed log batches still to
        download, the failing ones being retried. Honours the tenant selector and CIPP tenant access control.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $Now = [datetime]::UtcNow
    $LogNames = @{
        'Audit.AzureActiveDirectory' = 'Entra ID'
        'Audit.Exchange'             = 'Exchange'
        'Audit.SharePoint'           = 'SharePoint and OneDrive'
        'Audit.General'              = 'General (Teams and more)'
    }
    $Retrying = 'CIPP retries automatically, so this usually clears on its own. If it lasts more than a day, check Microsoft 365 service health for the audit log.'
    # What each error means and what to do, by the error code the feed stores.
    $Problems = @{
        AuditLogDisabled  = @{ Problem = 'Audit logging is off'; Detail = 'Unified audit logging is turned off in this tenant, so Microsoft keeps no audit log to read.'; Fix = 'Turn on unified audit logging (the "Enable the Unified Audit Log" standard). Microsoft can take up to 12 hours to start sending logs. CIPP checks again once a day.' }
        NoAuditLog        = @{ Problem = 'No audit log in this tenant'; Detail = 'The Office 365 Management APIs app is disabled in this tenant, which usually means no licence includes an audit log.'; Fix = 'Nothing to do unless the tenant gets a licence that includes auditing, such as Microsoft 365 Business Premium or E3. CIPP checks again once a day.' }
        Token             = @{ Problem = 'CIPP could not sign in'; Detail = 'CIPP could not get access to this tenant to read its audit log.'; Fix = 'Check the tenant''s GDAP relationship and run an Access Check for the tenant. A permissions refresh (CPV) usually fixes it.' }
        AF10001           = @{ Problem = 'Missing permission'; Detail = 'The CIPP app is missing the "Read activity data for your organization" permission in this tenant.'; Fix = 'Refresh the tenant''s permissions (CPV refresh) from the tenant list.' }
        AF20022           = @{ Problem = 'Log collection was not started'; Detail = 'Microsoft has no log subscription for CIPP in this tenant.'; Fix = 'CIPP starts it again automatically. If this stays, check audit logging is on in the tenant.' }
        AF20023           = @{ Problem = 'Log collection was turned off'; Detail = 'An admin of the tenant, or Microsoft, turned off the log subscription CIPP reads.'; Fix = 'CIPP tries to start it again. If this stays, check audit logging is on in the tenant.' }
        SubscriptionStart = @{ Problem = 'Could not start log collection'; Detail = 'Microsoft refused to start sending this log to CIPP.'; Fix = $Retrying }
        AF429             = @{ Problem = 'Microsoft is slowing CIPP down'; Detail = 'Microsoft is limiting how fast CIPP can read this tenant''s logs.'; Fix = 'No action needed. CIPP slows down and catches up.' }
    }

    try {
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        $CursorTable = Get-CippTable -TableName 'AuditLogFeedCursor'
        $Cursors = @{}
        foreach ($Row in @(Get-CIPPAzDataTableEntity @CursorTable)) { $Cursors['{0}|{1}' -f $Row.PartitionKey, $Row.RowKey] = $Row }
        $BlobTable = Get-CippTable -TableName 'AuditLogFeedBlobs'
        $Pending = @{}
        foreach ($Row in @(Get-CIPPAzDataTableEntity @BlobTable -Property @('PartitionKey', 'RowKey', 'ContentType', 'Attempts', 'LastError'))) {
            $Key = '{0}|{1}' -f $Row.PartitionKey, $Row.ContentType
            if (-not $Pending.ContainsKey($Key)) { $Pending[$Key] = @{ Count = 0; Failed = 0; Oldest = $null; LastError = $null } }
            $Feed = $Pending[$Key]
            $Feed.Count++
            if ($Row.LastError) { $Feed.Failed++; $Feed.LastError = $Row.LastError }
            # A blob row's RowKey starts with its created ticks.
            if ($null -eq $Feed.Oldest -or [string]::CompareOrdinal($Row.RowKey, $Feed.Oldest) -lt 0) { $Feed.Oldest = $Row.RowKey }
        }

        $Results = foreach ($Tenant in @(Get-CIPPAuditLogTenantScope)) {
            if ($AllowedTenants -notcontains 'AllTenants' -and $Tenant.customerId -notin $AllowedTenants) { continue }
            if ($TenantFilter -and $TenantFilter -ne 'AllTenants' -and $TenantFilter -notin @($Tenant.defaultDomainName, $Tenant.customerId)) { continue }
            foreach ($ContentType in $Tenant.ContentTypes) {
                $Cursor = $Cursors['{0}|{1}' -f $Tenant.defaultDomainName, $ContentType]
                $Feed = $Pending['{0}|{1}' -f $Tenant.defaultDomainName, $ContentType]
                $CheckedUpTo = if ($Cursor.LastEndUtc) { ([datetimeoffset]$Cursor.LastEndUtc).UtcDateTime }
                $Delay = if ($CheckedUpTo) { [int]($Now - $CheckedUpTo).TotalMinutes }
                $Code = [string]$Cursor.LastErrorCode
                $Status = if (-not $Cursor) { 'Waiting to start' }
                elseif ($Code -in @('AuditLogDisabled', 'NoAuditLog')) { 'Unavailable' }
                elseif ($Code) { 'Error, retrying' }
                elseif ($null -eq $Delay -or $Delay -gt 60) { 'Delayed' }
                else { 'Up to date' }
                $Explained = if ($Code) {
                    $Problems[$Code] ?? @{ Problem = 'Microsoft returned an error'; Detail = 'Reading this log from Microsoft failed.'; Fix = $Retrying }
                } elseif ($Status -eq 'Waiting to start') {
                    @{ Problem = 'Waiting for the first logs'; Detail = 'CIPP has not collected this log yet.'; Fix = 'No action needed. Microsoft can take up to 12 hours to send the first logs after collection starts.' }
                } elseif ($Status -eq 'Delayed') {
                    @{ Problem = 'Running behind'; Detail = 'Alerts for this log are more than an hour behind.'; Fix = 'CIPP is catching up. It reads back at most 6 hours, so activity older than that is not alerted on. If this stays, check CIPP''s background jobs are running.' }
                } elseif ($Feed.Failed -gt 0) {
                    @{ Problem = 'Some log batches failed to download'; Detail = 'Microsoft listed log batches CIPP could not download yet.'; Fix = 'CIPP retries each batch up to 5 times. ' + $Retrying }
                }
                [pscustomobject]@{
                    Tenant                    = $Tenant.defaultDomainName
                    TenantId                  = $Tenant.customerId
                    Log                       = $LogNames[$ContentType] ?? $ContentType
                    ContentType               = $ContentType
                    Status                    = $Status
                    Problem                   = $Explained.Problem
                    ProblemDetail             = $Explained.Detail
                    WhatToDo                  = $Explained.Fix
                    DelayMinutes              = if ($Status -ne 'Unavailable') { $Delay }
                    CheckedUpToDateTime       = $CheckedUpTo
                    CollectedUpToDateTime     = $Cursor.ListedThroughUtc
                    LastCollectedDateTime     = $Cursor.LastPolledUtc
                    LastSuccessDateTime       = $Cursor.LastSuccessUtc
                    NextTryDateTime           = $Cursor.NextAttemptUtc
                    Retries                   = [int]$Cursor.Attempts
                    ErrorCode                 = $Code
                    ErrorDetail               = $Cursor.LastError
                    ErrorDateTime             = $Cursor.LastErrorUtc
                    CollectionStartedDateTime = $Cursor.SubscriptionStartedUtc
                    BatchesFound              = $Cursor.Blobs
                    BatchesWaiting            = [int]$Feed.Count
                    BatchesFailing            = [int]$Feed.Failed
                    OldestWaitingDateTime     = if ($Feed.Oldest) { [datetime]::new([long]$Feed.Oldest.Substring(0, 19), [System.DateTimeKind]::Utc) }
                    LastBatchError            = $Feed.LastError
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        $Body = @($Results)
    } catch {
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $Body = @{ Results = "Could not read the audit log collection status: $($_.Exception.Message)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
