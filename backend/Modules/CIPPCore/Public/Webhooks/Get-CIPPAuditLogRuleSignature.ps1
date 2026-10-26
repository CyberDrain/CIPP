function Get-CIPPAuditLogRuleSignature {
    <#
    .SYNOPSIS
        A key that is equal for two tenants whose audit log rules compile to the same thing.
    .DESCRIPTION
        Rules is the tenant's Get-CIPPAuditLogRuleSet result. The key names each rule, marks the ones that exclude the
        tenant, and carries the resolved values of any rule whose conditions hold a %variable%, the only part of a rule
        that differs between tenants. Get-CIPPAuditLogPrefilter and Test-CIPPAuditLogRules compile once per key within a
        task, so a task holding many tenants compiles each distinct rule set once instead of once per tenant.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        $Rules
    )

    $Token = [regex]'%[A-Za-z][A-Za-z0-9_]*%'
    @(foreach ($Rule in @($Rules)) {
            $Key = [string]$Rule.RowKey
            if ($TenantFilter -in $Rule.Excluded.value) { $Key += '!' }
            if ($Token.IsMatch([string]$Rule.Conditions)) {
                $Resolved = try { Resolve-CIPPAuditLogConditionVariable -TenantFilter $TenantFilter -Conditions ([string]$Rule.Conditions | ConvertFrom-Json | Where-Object { $_.Input.value -ne '' }) -WarningAction SilentlyContinue } catch { 'unreadable' }
                $Key += '=' + [string](ConvertTo-Json -InputObject @($Resolved) -Compress -Depth 10)
            }
            $Key
        }) -join "`n"
}
