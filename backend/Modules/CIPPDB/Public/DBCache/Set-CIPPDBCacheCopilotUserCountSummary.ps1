function Set-CIPPDBCacheCopilotUserCountSummary {
    <#
    .SYNOPSIS
        Caches Microsoft 365 Copilot active user count summary by app for a tenant (30-day period, 28-day on report v2)

    .PARAMETER TenantFilter
        The tenant to cache Copilot user count summary for

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
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching Copilot user count summary' -sev Debug

        # D30 on report v1, D28 on v2 tenants - Get-CopilotReportPeriod falls back between them.
        $Data = Get-CopilotReportPeriod -UriTemplate "https://graph.microsoft.com/beta/reports/getMicrosoft365CopilotUserCountSummary(period='{0}')" -Period 'D30' -TenantFilter $TenantFilter -AsApp $true

        if ($Data) {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotUserCountSummary' -Data $Data -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached Copilot user count summary' -sev Debug
        } else {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'CopilotUserCountSummary' -Data @() -AddCount
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Copilot user count summary: no records returned (no active Copilot usage)' -sev Debug
        }

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache Copilot user count summary: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}
