function Get-CIPPAuditLogPrefilter {
    <#
    .SYNOPSIS
        Decides which raw audit records a tenant's rules could match, so only those are stored; $null keeps every record.
    .DESCRIPTION
        A record is kept unless every rule has a condition that is false on the raw record. Each rule becomes one script
        block of its conditions, each the string Test-CIPPAuditLogRules evaluates (Test-CIPPConditionFilter), so the
        operators behave exactly as they do there. A condition is only tested where the raw record holds the value the
        engine will see:
          - names the engine adds or rewrites (CIPP*, Previous_Value_*, clientip, HasLocationData, AuditRecord) and the
            sub-objects it removes (ExtendedProperties, DeviceProperties, parameters) are never tested, except CIPPActor,
            which is tested as the engine builds it: the record's Actor ids joined with ', ';
          - any other name counts as true on a record whose ExtendedProperties, DeviceProperties, parameters or
            ModifiedProperties hold an item of that Name, because the engine flattens that item over it.
        A rule the engine skips (a condition the sanitiser rejects, or no non-empty condition) matches nothing and is left
        out. A rule with no condition that can be tested matches anything, so the result is $null.

        Operations lists the eq/in/like values on Operation, for the blob check in Get-CIPPAuditLogContent; it is $null
        when a rule has none, since that rule can match a blob holding none of them. Anything unreadable keeps every record.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$TenantFilter)

    try {
        $Untested = '^(CIPP|Previous_Value_)|^(clientip|HasLocationData|AuditRecord|ExtendedProperties|DeviceProperties|parameters)$'
        $Operations = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::InvariantCultureIgnoreCase)
        $EveryRuleNamesOperations = $true
        $Rules = [System.Collections.Generic.List[scriptblock]]::new()
        foreach ($Rule in (Get-CIPPAuditLogRuleSet -TenantFilter $TenantFilter)) {
            if ($TenantFilter -in $Rule.Excluded.value) { continue }
            # The engine's own selection of a rule's conditions.
            $Conditions = $Rule.Conditions | ConvertFrom-Json | Where-Object { $_.Input.value -ne '' }
            $Terms = [System.Collections.Generic.List[string]]::new()
            $RuleOperations = [System.Collections.Generic.List[string]]::new()
            $Skipped = $false
            $Count = 0
            foreach ($Condition in $Conditions) {
                $Sanitized = Test-CIPPConditionFilter -Condition $Condition
                if ($null -eq $Sanitized) { $Skipped = $true; break }
                $Count++
                # The sanitiser allows only [A-Za-z0-9_.] in a label, so the root name is safe inside quotes.
                $Root = ([string]$Condition.Property.label -split '\.', 2)[0]
                if ($Condition.Property.label -eq 'CIPPActor') {
                    $Sanitized = $Sanitized.Replace('$($_.CIPPActor)', '$(if ($_.Actor) { @(foreach ($ActorEntry in $_.Actor) { [string]$ActorEntry.ID }) -join '', '' } else { $null })')
                } elseif ($Root -match $Untested) { continue }
                $Terms.Add("(($Sanitized) -or `$_.ExtendedProperties.Name -contains '$Root' -or `$_.DeviceProperties.Name -contains '$Root' -or `$_.parameters.Name -contains '$Root' -or `$_.ModifiedProperties.Name -contains '$Root')")
                if ($Root -eq 'Operation' -and [string]$Condition.Operator.value -in @('eq', 'in', 'like')) {
                    foreach ($Value in @($Condition.Input.value)) { $RuleOperations.Add([string]$Value) }
                }
            }
            if ($Skipped -or $Count -eq 0) { continue }
            if ($Terms.Count -eq 0) { return $null }
            if ($RuleOperations.Count -eq 0) { $EveryRuleNamesOperations = $false }
            foreach ($Value in $RuleOperations) { [void]$Operations.Add($Value) }
            $Rules.Add([scriptblock]::Create($Terms -join ' -and '))
        }
        [pscustomobject]@{
            Rules      = $Rules.ToArray()
            Operations = if ($EveryRuleNamesOperations) { , $Operations } else { $null }
        }
    } catch {
        Write-Information "Audit log prefilter for $TenantFilter could not be built, keeping every record: $($_.Exception.Message)"
        $null
    }
}
