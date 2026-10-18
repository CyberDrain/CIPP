function New-CippAuditLogClaimRow {
    <#
    .SYNOPSIS
        The AuditLogs claim row for a matched audit record.
    .DESCRIPTION
        The record Id alone does not identify an event: Entra sign-in records reuse the same Id for the same user weeks
        apart, so a claim from an old sign-in would swallow every later one. The claim therefore carries the event's own
        time as EventCreationTime (yyyyMMddHHmmss, UTC), and a key conflict only yields to a strictly newer event. It is
        empty when the record has no CreationTime, which falls back to dedupe on the Id alone. The RowKey stays the bare
        Id so the audit-log link, the Saved Logs list endpoint and the split-row OriginalEntityId lookup all keep working.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)]$Data
    )

    $EventStamp = ''
    $CreationTime = $Data.CreationTime ?? $Data.RawData.CreationTime ?? $Data.createdDateTime
    if ($CreationTime -is [datetime]) {
        $EventStamp = $CreationTime.ToUniversalTime().ToString('yyyyMMddHHmmss')
    } elseif ($CreationTime) {
        $ParsedCreation = [datetime]::MinValue
        $CreationStyles = [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal
        if ([datetime]::TryParse([string]$CreationTime, [cultureinfo]::InvariantCulture, $CreationStyles, [ref]$ParsedCreation)) {
            $EventStamp = $ParsedCreation.ToString('yyyyMMddHHmmss')
        }
    }

    @{
        PartitionKey      = $TenantFilter
        RowKey            = $Data.Id
        Title             = 'Processing'
        Tenant            = $TenantFilter
        EventCreationTime = $EventStamp
    }
}
