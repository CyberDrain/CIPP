function Get-CIPPAuditLogPrefilter {
    <#
    .SYNOPSIS
        Decides which raw audit records a tenant's rules could match, so only those are processed; $null keeps every record.
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
        A rule the engine skips (a condition the sanitiser rejects, no non-empty condition, or no anchor from
        Get-CIPPAuditLogRuleAnchor) matches nothing and is left out.

        Needles holds every kept rule's anchor needles, for the blob check in Get-CIPPAuditLogContent; with no rules it is
        empty and every blob is skipped. Index holds each rule's anchor, so Select-CIPPAuditLogCandidate runs a record
        only through the rules its Operation can satisfy; ByOperation memoises that choice per Operation. Each entry's
        Location is the rule's location conditions (CIPPGeoLocation, CIPPBadRepIP, CIPPHostedIP), or $null when it has
        none, so a record whose every possible rule needs a location its address does not have is dropped before it is
        built; Geo and Gates memoise the addresses and answers. Anything unreadable keeps every record.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$TenantFilter)

    try {
        $Untested = '^(CIPP|Previous_Value_)|^(clientip|HasLocationData|AuditRecord|ExtendedProperties|DeviceProperties|parameters)$'
        $Needles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Rules = [System.Collections.Generic.List[scriptblock]]::new()
        $Index = [System.Collections.Generic.List[object]]::new()
        foreach ($Rule in (Get-CIPPAuditLogRuleSet -TenantFilter $TenantFilter)) {
            if ($TenantFilter -in $Rule.Excluded.value) { continue }
            # The engine's own selection of a rule's conditions.
            $Conditions = $Rule.Conditions | ConvertFrom-Json | Where-Object { $_.Input.value -ne '' }
            $Terms = [System.Collections.Generic.List[string]]::new()
            $Anchor = Get-CIPPAuditLogRuleAnchor -Conditions $Conditions
            if ($null -eq $Anchor) { continue }
            $Skipped = $false
            $Count = 0
            $LocationTerms = [System.Collections.Generic.List[string]]::new()
            foreach ($Condition in $Conditions) {
                $Sanitized = Test-CIPPConditionFilter -Condition $Condition
                if ($null -eq $Sanitized) { $Skipped = $true; break }
                $Count++
                # The sanitiser allows only [A-Za-z0-9_.] in a label, so the root name is safe inside quotes.
                $Root = ([string]$Condition.Property.label -split '\.', 2)[0]
                if ($Root -match '^CIPP(GeoLocation|BadRepIP|HostedIP)$') { $LocationTerms.Add("($Sanitized)") }
                if ($Condition.Property.label -eq 'CIPPActor') {
                    $Sanitized = $Sanitized.Replace('$($_.CIPPActor)', '$(if ($_.Actor) { @(foreach ($ActorEntry in $_.Actor) { [string]$ActorEntry.ID }) -join '', '' } else { $null })')
                } elseif ($Root -match $Untested) { continue }
                $Terms.Add("(($Sanitized) -or `$_.ExtendedProperties.Name -contains '$Root' -or `$_.DeviceProperties.Name -contains '$Root' -or `$_.parameters.Name -contains '$Root' -or `$_.ModifiedProperties.Name -contains '$Root')")
            }
            if ($Skipped -or $Count -eq 0) { continue }
            foreach ($Needle in $Anchor.Needles) { [void]$Needles.Add($Needle) }
            # The anchor is an Operation condition, which is always tested, so Terms is never empty here.
            $Block = [scriptblock]::Create($Terms -join ' -and ')
            $Rules.Add($Block)
            # As the engine does, a location condition needs location data, which no reserved or unresolved address has.
            $Location = if ($LocationTerms.Count -gt 0) { [scriptblock]::Create('$_.HasLocationData -eq $true -and ' + ($LocationTerms -join ' -and ')) }
            $Index.Add([pscustomobject]@{ Rule = $Block; Literals = $Anchor.Literals; Patterns = $Anchor.Patterns; Location = $Location })
        }
        [pscustomobject]@{
            Rules       = $Rules.ToArray()
            Needles     = @($Needles)
            Index       = $Index.ToArray()
            # Operation -> the Index entries a record with that Operation can match, and whether every one of them needs a
            # location, filled by Select-CIPPAuditLogCandidate.
            ByOperation = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::InvariantCultureIgnoreCase)
            # Normalised address -> what the engine will see of its location ($null for none); "<operation>`n<address>" -> kept.
            Geo         = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            Gates       = [System.Collections.Generic.Dictionary[string, bool]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
    } catch {
        Write-Information "Audit log prefilter for $TenantFilter could not be built, keeping every record: $($_.Exception.Message)"
        $null
    }
}
