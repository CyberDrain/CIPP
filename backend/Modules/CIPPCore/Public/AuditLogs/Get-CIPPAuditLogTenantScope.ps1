function Get-CIPPAuditLogTenantScope {
    <#
    .SYNOPSIS
        The tenants enabled audit log rules apply to, with the content types those rules read.
    .DESCRIPTION
        Tenants covered by an enabled Webhookv2 rule (tenant groups expanded), minus each rule's exclusions and minus
        tenants in AuditLogDisabledTenants whose disable has not expired. Returns
        [pscustomobject]@{ defaultDomainName; customerId; ContentTypes }, where ContentTypes holds the rules' Type
        values (Audit.Exchange / Audit.AzureActiveDirectory); a rule without a Type counts as both.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $AllContentTypes = @('Audit.AzureActiveDirectory', 'Audit.Exchange')
    $ConfigTable = Get-CippTable -TableName 'WebhookRules'
    $ConfigEntries = @(Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'Webhookv2'").Where({ $_.Disabled -ne $true })
    if ($ConfigEntries.Count -eq 0) { return @() }

    # Hoisted into hash sets once per rule: -contains per tenant per rule is a linear scan.
    $RuleScopes = foreach ($ConfigEntry in $ConfigEntries) {
        $Included = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Name in @((Expand-CIPPTenantGroups -TenantFilter ($ConfigEntry.Tenants | ConvertFrom-Json)).value)) {
            if ($Name) { [void]$Included.Add([string]$Name) }
        }
        $Excluded = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        if ($ConfigEntry.excludedTenants) {
            $ExcludedList = $ConfigEntry.excludedTenants | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($ExcludedList) {
                foreach ($Name in @((Expand-CIPPTenantGroups -TenantFilter $ExcludedList).value)) {
                    if ($Name) { [void]$Excluded.Add([string]$Name) }
                }
            }
        }
        [PSCustomObject]@{
            Included     = $Included
            Excluded     = $Excluded
            AllTenants   = $Included.Contains('AllTenants')
            ContentTypes = if ($ConfigEntry.Type -in $AllContentTypes) { @([string]$ConfigEntry.Type) } else { $AllContentTypes }
        }
    }

    $AuditDisabledTable = Get-CIPPTable -TableName 'AuditLogDisabledTenants'
    $NowUnix = [int64]([datetimeoffset]::UtcNow.ToUnixTimeSeconds())
    $AuditDisabledTenants = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($DisabledRow in @(Get-CIPPAzDataTableEntity @AuditDisabledTable -Filter "PartitionKey eq 'AuditDisabledTenant'")) {
        [int64]$ExpiresAtUnix = 0
        if ([int64]::TryParse([string]$DisabledRow.ExpiresAtUnix, [ref]$ExpiresAtUnix) -and $ExpiresAtUnix -gt $NowUnix) {
            [void]$AuditDisabledTenants.Add([string]$DisabledRow.RowKey)
        }
    }

    foreach ($Tenant in (Get-Tenants -IncludeErrors)) {
        $DomainName = [string]$Tenant.defaultDomainName
        if ($AuditDisabledTenants.Contains($DomainName) -or $AuditDisabledTenants.Contains([string]$Tenant.customerId)) { continue }
        $ContentTypes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Scope in $RuleScopes) {
            if ($Scope.Excluded.Contains($DomainName)) { continue }
            if ($Scope.AllTenants -or $Scope.Included.Contains($DomainName)) {
                foreach ($ContentType in $Scope.ContentTypes) { [void]$ContentTypes.Add($ContentType) }
            }
        }
        if ($ContentTypes.Count -gt 0) {
            [PSCustomObject]@{
                defaultDomainName = $DomainName
                customerId        = [string]$Tenant.customerId
                ContentTypes      = [string[]]@($ContentTypes)
            }
        }
    }
}
