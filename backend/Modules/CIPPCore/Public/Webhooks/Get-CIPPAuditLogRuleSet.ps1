function Get-CIPPAuditLogRuleSet {
    <#
    .SYNOPSIS
        The enabled audit log alert rules whose tenants cover a tenant.
    .DESCRIPTION
        Reads WebhookRules, expands tenant groups and returns one object per rule that applies to
        TenantFilter (Tenants, Excluded, Conditions, Actions, BecActions, LogType, AlertComment,
        CustomSubject, PsaTicketPriority, RowKey, Threshold, Priority), rules with a Priority first (lowest first) and the rest in
        stored order. Exclusions are expanded only for rules that cover the tenant,
        since each expansion reads the tenant list.

        The expanded rule set is memoised for two minutes. Script scope lasts one worker invocation, so
        the memo serves the slices of one task and a rule edit is picked up by the next task.
    .PARAMETER TenantFilter
        The tenant's default domain.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$TenantFilter)

    $Now = [datetime]::UtcNow
    if ($null -eq $script:AuditRuleSetCache -or $script:AuditRuleSetCache.Expires -le $Now) {
        $ConfigTable = Get-CIPPTable -TableName 'WebhookRules'
        $Order = 0
        $Rules = foreach ($ConfigEntry in (Get-CIPPAzDataTableEntity @ConfigTable)) {
            if ($ConfigEntry.Disabled -eq $true) {
                continue
            }
            if ([string]::IsNullOrEmpty($ConfigEntry.Tenants)) {
                continue
            }
            $Tenants = $ConfigEntry.Tenants | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($null -eq $Tenants) {
                continue
            }
            [pscustomobject]@{
                Order            = $Order++
                Expanded         = @((Expand-CIPPTenantGroups -TenantFilter $Tenants).value)
                ExcludedTenants  = $ConfigEntry.excludedTenants
                ExcludedExpanded = $false
                Rule             = [pscustomobject]@{
                    Tenants           = $Tenants
                    Excluded          = $null
                    Conditions        = $ConfigEntry.Conditions
                    Actions           = $ConfigEntry.Actions
                    BecActions        = $ConfigEntry.BecActions
                    LogType           = $ConfigEntry.Type
                    AlertComment      = $ConfigEntry.AlertComment
                    CustomSubject     = $ConfigEntry.CustomSubject
                    PsaTicketPriority = $ConfigEntry.PsaTicketPriority
                    RowKey            = $ConfigEntry.RowKey
                    # Backend-only threshold rules: '{"Count":100,"Minutes":20}' alerts once one identity's records of the
                    # rule's operations reach Count within Minutes, instead of on each record.
                    Threshold         = $ConfigEntry.Threshold
                    Priority          = if ([string]$ConfigEntry.Priority -match '^\d+$') { [int]$ConfigEntry.Priority }
                }
            }
        }
        # Rules with a priority first, lowest number first, then the rest in stored order; a record alerts on the first it matches.
        $Rules = @($Rules | Sort-Object -Property @{ Expression = { $null -eq $_.Rule.Priority } }, @{ Expression = { $_.Rule.Priority } }, Order)
        $script:AuditRuleSetCache = [pscustomobject]@{ Expires = $Now.AddMinutes(2); Rules = @($Rules) }
    }

    foreach ($Entry in $script:AuditRuleSetCache.Rules) {
        if ($Entry.Expanded -notcontains $TenantFilter -and $Entry.Expanded -notcontains 'AllTenants') { continue }
        if (-not $Entry.ExcludedExpanded) {
            $ExcludedTenants = $Entry.ExcludedTenants | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($ExcludedTenants) {
                $ExcludedTenants = @(Expand-CIPPTenantGroups -TenantFilter $ExcludedTenants)
            }
            $Entry.Rule.Excluded = $ExcludedTenants
            $Entry.ExcludedExpanded = $true
        }
        $Entry.Rule
    }
}
