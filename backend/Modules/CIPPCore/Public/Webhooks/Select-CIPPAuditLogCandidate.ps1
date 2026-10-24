function Select-CIPPAuditLogCandidate {
    <#
    .SYNOPSIS
        The records a Get-CIPPAuditLogPrefilter result keeps: those at least one rule could match.
    .DESCRIPTION
        Records: a Graph search record is tested on its auditData, which is what Test-CIPPAuditLogRules matches; a feed
        record is the audit record itself. A rule that throws on a record keeps it. A $null prefilter keeps every record.

        Index (a [CIPP.CippJson]::IndexRecords index of Operation and ClientIP): only the records worth building are
        built, then tested as above. A record is worth building when its Operation can satisfy a rule's anchor and, if
        every such rule has location conditions, its address resolves to a location one of them accepts (addresses are
        resolved once per prefilter, in one batch per call). The caller must not index a blob in which an item named
        Operation or ClientIP could replace the record's own, since the engine flattens such items over them.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Prefilter,
        [object[]]$Records,
        $Index
    )

    # Operation -> the Index entries it can satisfy, their rules, and whether every one of them needs a location; memoised.
    $Choose = {
        param($Operation)
        $Entries = @(foreach ($Entry in $Prefilter.Index) {
                if ($Entry.Literals.Contains($Operation) -or $Entry.Patterns.Where({ $_.IsMatch($Operation) }, 'First').Count -gt 0) { $Entry }
            })
        $Choice = [pscustomobject]@{ Entries = $Entries; Rules = @(foreach ($Entry in $Entries) { $Entry.Rule }); Gated = $Entries.Count -gt 0 -and $Entries.Where({ $null -eq $_.Location }, 'First').Count -eq 0 }
        $Prefilter.ByOperation[$Operation] = $Choice
        $Choice
    }

    if ($null -ne $Index) {
        if ($Index.Count -eq 0) { return }
        if ($null -eq $Prefilter) { return [CIPP.CippJson]::ConvertFromIndex($Index, [int[]](0..($Index.Count - 1))) }
        # The engine's normalisation of a client address (no port, no brackets).
        $IpRegex = [regex]'^(?<IP>(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+))(?::\d+)?$'
        $Ops = $Index.Values[0]
        $Ips = $Index.Values[1]
        $Keep = [bool[]]::new($Index.Count)
        $Pending = [System.Collections.Generic.List[int]]::new()
        $Lookup = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        for ($i = 0; $i -lt $Ops.Length; $i++) {
            $Operation = [string]$Ops[$i]
            $Choice = $null
            if (-not $Prefilter.ByOperation.TryGetValue($Operation, [ref]$Choice)) { $Choice = & $Choose $Operation }
            if ($Choice.Entries.Count -eq 0) { continue }
            if (-not $Choice.Gated) { $Keep[$i] = $true; continue }
            # Every rule needs a location: no address, or one the engine cannot place, cannot match.
            $Ip = [string]$Ips[$i]
            if (-not $Ip -or $Ip -match '[X]+') { continue }
            $Ip = $IpRegex.Replace($Ip, '$1') -replace '[\[\]]', ''
            $Ips[$i] = $Ip
            if (-not $Prefilter.Geo.ContainsKey($Ip)) { [void]$Lookup.Add($Ip) }
            $Pending.Add($i)
        }
        if ($Lookup.Count -gt 0) {
            $Found = try { Get-CIPPGeoIPLocationBatch -IPs @($Lookup) } catch { @{} }
            foreach ($Ip in $Lookup) {
                $Loc = $Found[$Ip]
                $Prefilter.Geo[$Ip] = if ($Loc) { [pscustomobject]@{ HasLocationData = $true; CIPPGeoLocation = $Loc.CountryOrRegion; CIPPBadRepIP = $Loc.Proxy; CIPPHostedIP = $Loc.Hosting } }
            }
        }
        foreach ($i in $Pending) {
            $Key = "$($Ops[$i])`n$($Ips[$i])"
            $Kept = $false
            if (-not $Prefilter.Gates.TryGetValue($Key, [ref]$Kept)) {
                $Seen = $Prefilter.Geo[$Ips[$i]]
                $Kept = $null -ne $Seen -and $Prefilter.ByOperation[[string]$Ops[$i]].Entries.Where({ @($Seen).Where($_.Location, 'First').Count -gt 0 }, 'First').Count -gt 0
                $Prefilter.Gates[$Key] = $Kept
            }
            $Keep[$i] = $Kept
        }
        $Picked = [System.Collections.Generic.List[int]]::new()
        for ($i = 0; $i -lt $Keep.Length; $i++) { if ($Keep[$i]) { $Picked.Add($i) } }
        if ($Picked.Count -eq 0) { return }
        $Records = [CIPP.CippJson]::ConvertFromIndex($Index, $Picked.ToArray())
    }

    foreach ($Record in $Records) {
        $View = $Record.auditData ?? $Record
        if ($null -eq $Prefilter -or $null -eq $View) { $Record; continue }
        $Rules = $Prefilter.Rules
        # A rule can only match a record whose Operation its anchor allows, unless the engine's flattening of an item
        # named Operation replaces the record's own.
        if ($Prefilter.Index -and -not ($View.ExtendedProperties.Name -contains 'Operation' -or $View.DeviceProperties.Name -contains 'Operation' -or $View.parameters.Name -contains 'Operation' -or $View.ModifiedProperties.Name -contains 'Operation')) {
            $Operation = [string]$View.Operation
            $Choice = $null
            if (-not $Prefilter.ByOperation.TryGetValue($Operation, [ref]$Choice)) { $Choice = & $Choose $Operation }
            $Rules = $Choice.Rules
        }
        foreach ($Rule in $Rules) {
            $Kept = try { @($View).Where($Rule, 'First').Count -gt 0 } catch { $true }
            if ($Kept) { $Record; break }
        }
    }
}
