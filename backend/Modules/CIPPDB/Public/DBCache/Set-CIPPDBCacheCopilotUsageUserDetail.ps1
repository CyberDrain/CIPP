function Set-CIPPDBCacheCopilotUsageUserDetail {
    <#
    .SYNOPSIS
        Caches per-user Microsoft 365 Copilot usage details for a tenant (30-day period, 28-day on report v2)

    .PARAMETER TenantFilter
        The tenant to cache Copilot usage user detail for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Copilot usage user detail' -sev Debug

        # Streamed into the writer: this report returns a row per user and is iterated once, so
        # there is no reason to hold the whole set. Both previous branches ended in an
        # Add-CIPPDbItem call - the empty one wrote the -Data @() marker - and a pipeline that
        # yields nothing still runs the writer's end block, so that marker is still written.
        # D30 on report v1, D28 on v2 tenants - Get-CopilotReportPeriod falls back between them.
        $CachedRecords = 0
        Get-CopilotReportPeriod -UriTemplate "https://graph.microsoft.com/beta/reports/getMicrosoft365CopilotUsageUserDetail(period='{0}')" -Period 'D30' -TenantFilter $TenantFilter -AsApp $true -Stream |
            ForEach-Object { $CachedRecords++; $_ } |
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotUsageUserDetail' -AddCount

        if ($CachedRecords -gt 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached $CachedRecords Copilot usage user detail records" -sev Debug
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Copilot usage user detail: no records returned (no active Copilot usage)' -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Copilot usage user detail: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}
