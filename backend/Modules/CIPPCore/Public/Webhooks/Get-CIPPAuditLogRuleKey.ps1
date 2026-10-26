function Get-CIPPAuditLogRuleKey {
    <#
    .SYNOPSIS
        A key that is equal for two tenants on which an audit log rule compiles to the same thing.
    .DESCRIPTION
        Rule is a Get-CIPPAuditLogRuleSet entry. The key is the rule's RowKey, plus the resolved values when its conditions
        hold a %variable%, the only part of a rule's conditions that differs between tenants. Get-CIPPAuditLogPrefilter and
        Test-CIPPAuditLogRules compile each rule once per key within a task, so a task holding many tenants compiles each
        rule once however the rules are scoped to tenants and groups.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        $Rule
    )

    if ([string]$Rule.Conditions -notmatch '%[A-Za-z][A-Za-z0-9_]*%') { return [string]$Rule.RowKey }
    $Resolved = try { Resolve-CIPPAuditLogConditionVariable -TenantFilter $TenantFilter -Conditions ([string]$Rule.Conditions | ConvertFrom-Json | Where-Object { $_.Input.value -ne '' }) -WarningAction SilentlyContinue } catch { 'unreadable' }
    '{0}={1}' -f $Rule.RowKey, [string](ConvertTo-Json -InputObject @($Resolved) -Compress -Depth 10)
}
