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
        built; Geo and Gates memoise the addresses and answers. Groups are the rule's needle groups: each positive
        condition on a raw name (eq, like or in) needs that name, and, when its values hold letters, their longest plain
        run of text (for in, one of its values'), somewhere in the record's raw text, so RecordNeedles (up to 64) lets an index rule a record
        out without building it. Thresholds holds the backend-only threshold rules (a Threshold of '{"Count":N,"Minutes":M}' and an
        Operation eq/in anchor): they never match a record on its own, so they are not in Index, but their operations are
        needles, and Push-AuditLogFeedBlobsV3 counts them per identity. Anything unreadable keeps every record.
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
        $RecordNeedles = [System.Collections.Generic.List[string]]::new()
        $Thresholds = [System.Collections.Generic.List[object]]::new()
        # Text JSON writes as is and every serialiser leaves alone.
        $PlainRun = [regex]'[A-Za-z0-9 ._@:-]{3,}'
        foreach ($Rule in (Get-CIPPAuditLogRuleSet -TenantFilter $TenantFilter)) {
            if ($TenantFilter -in $Rule.Excluded.value) { continue }
            # The engine's own selection of a rule's conditions.
            $Conditions = $Rule.Conditions | ConvertFrom-Json | Where-Object { $_.Input.value -ne '' }
            $Terms = [System.Collections.Generic.List[string]]::new()
            $Anchor = Get-CIPPAuditLogRuleAnchor -Conditions $Conditions
            if ($null -eq $Anchor) { continue }
            if ($Rule.Threshold) {
                $Setting = try { [string]$Rule.Threshold | ConvertFrom-Json -ErrorAction Stop } catch { $null }
                # Counting needs the exact operations, so a like anchor cannot be a threshold rule.
                if ([int]$Setting.Count -gt 0 -and $Anchor.Patterns.Count -eq 0) {
                    foreach ($Needle in $Anchor.Needles) { [void]$Needles.Add($Needle) }
                    $Thresholds.Add([pscustomobject]@{ Rule = $Rule; Operations = [string[]]@($Anchor.Literals); Count = [int]$Setting.Count; Minutes = [Math]::Max(10, [int]($Setting.Minutes ?? 20)) })
                }
                continue
            }
            $Skipped = $false
            $Count = 0
            $LocationTerms = [System.Collections.Generic.List[string]]::new()
            $Groups = [System.Collections.Generic.List[uint64]]::new()
            foreach ($Condition in $Conditions) {
                $Sanitized = Test-CIPPConditionFilter -Condition $Condition
                if ($null -eq $Sanitized) { $Skipped = $true; break }
                $Count++
                # The sanitiser allows only [A-Za-z0-9_.] in a label, so the root name is safe inside quotes.
                $Root = ([string]$Condition.Property.label -split '\.', 2)[0]
                if ($Root -match '^CIPP(GeoLocation|BadRepIP|HostedIP)$') { $LocationTerms.Add("($Sanitized)") }
                $Operator = ([string]$Condition.Operator.value).ToLowerInvariant()
                if ($Root -ne 'Operation' -and $Operator -in 'eq', 'like', 'in' -and ($Root -notmatch $Untested -or $Root -in 'CIPPActor', 'CIPPAddedKeyTypes')) {
                    $Group = [uint64]0
                    foreach ($Value in @($Condition.Input.value)) {
                        $Longest = ''
                        if ([string]$Value -match '[A-Za-z]') {
                            foreach ($Run in $PlainRun.Matches(([string]$Value -replace '[*?\[\]]', "`n"))) { if ($Run.Value.Length -gt $Longest.Length) { $Longest = $Run.Value } }
                        }
                        # A value with no usable text leaves the condition without a needle.
                        if (-not $Longest) { $Group = 0; break }
                        $At = $RecordNeedles.IndexOf($Longest.ToLowerInvariant())
                        if ($At -lt 0 -and $RecordNeedles.Count -lt 64) { $RecordNeedles.Add($Longest.ToLowerInvariant()); $At = $RecordNeedles.Count - 1 }
                        if ($At -lt 0) { $Group = 0; break }
                        $Group = $Group -bor ([uint64]1 -shl $At)
                    }
                    if ($Group) { $Groups.Add($Group) }
                    # The engine only has a value for a raw name the record carries, as a field or as an item's Name.
                    if ($Root -notmatch $Untested -and $Root.Length -ge 3) {
                        $At = $RecordNeedles.IndexOf($Root.ToLowerInvariant())
                        if ($At -lt 0 -and $RecordNeedles.Count -lt 64) { $RecordNeedles.Add($Root.ToLowerInvariant()); $At = $RecordNeedles.Count - 1 }
                        if ($At -ge 0) { $Groups.Add([uint64]1 -shl $At) }
                    }
                }
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
            $Index.Add([pscustomobject]@{ Rule = $Block; Literals = $Anchor.Literals; Patterns = $Anchor.Patterns; Location = $Location; Groups = $Groups.ToArray() })
        }
        [pscustomobject]@{
            Rules       = $Rules.ToArray()
            Needles     = @($Needles)
            RecordNeedles = $RecordNeedles.ToArray()
            Thresholds  = $Thresholds.ToArray()
            Index       = $Index.ToArray()
            # Operation -> the Index entries a record with that Operation can match, and whether every one of them needs a
            # location, filled by Select-CIPPAuditLogCandidate.
            ByOperation = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::InvariantCultureIgnoreCase)
            # Normalised address -> what the engine will see of its location ($null for none); "<operation>`n<address>" -> kept.
            Geo         = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
            Gates       = [System.Collections.Generic.Dictionary[string, bool]]::new([System.StringComparer]::OrdinalIgnoreCase)
            # "<operation>`n<needle mask>" -> the entries a record with that Operation and text can match.
            Masked      = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::InvariantCultureIgnoreCase)
        }
    } catch {
        Write-Information "Audit log prefilter for $TenantFilter could not be built, keeping every record: $($_.Exception.Message)"
        $null
    }
}
