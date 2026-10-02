function Get-CopilotReportPeriod {
    <#
    .SYNOPSIS
        Runs a Copilot usage report request, retrying once with the other 28/30-day period
        when Graph rejects the requested one for the tenant's report version.
    .DESCRIPTION
        Copilot reports v1 take D30, v2 takes D28 and rejects D30 (as RL30), and the reverse.
        Tenants are moving to v2 as the default at different times, so callers pass the period
        they prefer in a '{0}' URI template and this falls back on that specific Graph error.
        Any other error is rethrown unchanged.

        With -Stream the rejected request throws before its first page is emitted, so the
        retry still feeds a downstream pipeline consumer cleanly.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$UriTemplate,
        [Parameter(Mandatory)][string]$Period,
        [Parameter(Mandatory)][string]$TenantFilter,
        $AsApp,
        [switch]$Stream
    )

    $Request = @{ tenantid = $TenantFilter; AsApp = $AsApp; Stream = $Stream }
    try {
        return New-GraphGetRequest -Uri ($UriTemplate -f $Period) @Request
    } catch {
        $Alternate = switch ($Period) {
            'D30' { 'D28' }
            'D28' { 'D30' }
            default { $null }
        }
        $Message = "$($_.Exception.Message)"
        if ($Alternate -and $Message -match "period value 'RL(30|28)' is not supported|Use 'RL(28|30)' instead") {
            Write-Information "Copilot report period '$Period' rejected for $TenantFilter; retrying with '$Alternate'."
            return New-GraphGetRequest -Uri ($UriTemplate -f $Alternate) @Request
        }
        throw
    }
}
