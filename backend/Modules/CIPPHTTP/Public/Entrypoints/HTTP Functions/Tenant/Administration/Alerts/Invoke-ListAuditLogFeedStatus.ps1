function Invoke-ListAuditLogFeedStatus {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        Tenant.Alert.Read
    .SYNOPSIS
        Lists how far the audit log feed has read for each tenant and content type.
    .DESCRIPTION
        One row per tenant in audit log alert scope and content type, from its AuditLogFeedCursor row: Status (Healthy,
        Behind, Backing off, Parked, Not started), CoveredUntil, LagMinutes, the last poll and success, the next attempt,
        the last error, and the last read's blob, record and stored counts. Parked means the tenant has no audit log to
        read and is checked once a day. Honours the tenant selector and CIPP tenant access control.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    $Now = [datetime]::UtcNow

    try {
        $AllowedTenants = Test-CIPPAccess -Request $Request -TenantList
        $CursorTable = Get-CippTable -TableName 'AuditLogFeedCursor'
        $Cursors = @{}
        foreach ($Row in @(Get-CIPPAzDataTableEntity @CursorTable)) { $Cursors['{0}|{1}' -f $Row.PartitionKey, $Row.RowKey] = $Row }

        $Results = foreach ($Tenant in @(Get-CIPPAuditLogTenantScope)) {
            if ($AllowedTenants -notcontains 'AllTenants' -and $Tenant.customerId -notin $AllowedTenants) { continue }
            if ($TenantFilter -and $TenantFilter -ne 'AllTenants' -and $TenantFilter -notin @($Tenant.defaultDomainName, $Tenant.customerId)) { continue }
            foreach ($ContentType in $Tenant.ContentTypes) {
                $Cursor = $Cursors['{0}|{1}' -f $Tenant.defaultDomainName, $ContentType]
                $CoveredUntil = if ($Cursor.LastEndUtc) { ([datetimeoffset]$Cursor.LastEndUtc).UtcDateTime }
                $Lag = if ($CoveredUntil) { [int]($Now - $CoveredUntil).TotalMinutes }
                $Status = if (-not $Cursor) { 'Not started' }
                elseif ($Cursor.LastErrorCode -in @('AuditLogDisabled', 'NoAuditLog')) { 'Parked' }
                elseif ($Cursor.LastErrorCode) { 'Backing off' }
                elseif ($null -eq $Lag -or $Lag -gt 60) { 'Behind' }
                else { 'Healthy' }
                [pscustomobject]@{
                    Tenant                 = $Tenant.defaultDomainName
                    TenantId               = $Tenant.customerId
                    ContentType            = $ContentType
                    Status                 = $Status
                    CoveredUntil           = $CoveredUntil
                    LagMinutes             = $Lag
                    LastPolledUtc          = $Cursor.LastPolledUtc
                    LastSuccessUtc         = $Cursor.LastSuccessUtc
                    NextAttemptUtc         = $Cursor.NextAttemptUtc
                    Attempts               = [int]$Cursor.Attempts
                    LastErrorCode          = $Cursor.LastErrorCode
                    LastError              = $Cursor.LastError
                    LastErrorUtc           = $Cursor.LastErrorUtc
                    SubscriptionStartedUtc = $Cursor.SubscriptionStartedUtc
                    Blobs                  = $Cursor.Blobs
                    Records                = $Cursor.Records
                    Stored                 = $Cursor.Stored
                }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
        $Body = @($Results)
    } catch {
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $Body = @{ Results = "Could not read the audit log feed status: $($_.Exception.Message)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
