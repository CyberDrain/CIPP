function Set-CIPPDBCacheLicenseChanges {
    <#
    .SYNOPSIS
        Caches the licences added to and removed from users in the last 30 days

    .DESCRIPTION
        Reads successful 'Change user license' events from the directory audit log (needs Entra ID P1) and
        keeps one row per licence added or removed, with the user and who made the change, a user or an app.
        A failed read writes nothing and rethrows.

    .PARAMETER TenantFilter
        The tenant to cache licence changes for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching licence changes' -sev Debug

        $Start = [datetime]::UtcNow.AddDays(-30).ToString('s') + 'Z'
        $Uri = "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Change user license' and activityDateTime ge $Start&`$select=id,activityDateTime,activityDisplayName,result,initiatedBy,targetResources,additionalDetails&`$top=999"
        $Rows = @(New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -AsApp $true -Stream | ConvertFrom-CIPPLicenseAuditEvent -TenantFilter $TenantFilter)

        if ($Rows.Count -gt 0) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'LicenseChanges' -Data $Rows -AddCount
        } else {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'LicenseChanges' -Data @() -AddCount -ClearOnEmpty
        }
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $($Rows.Count) licence changes" -sev Debug
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache licence changes: $($_.Exception.Message)" -sev Error
        throw
    }
}
