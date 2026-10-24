function Get-CIPPAuditLogRuleAnchor {
    <#
    .SYNOPSIS
        The cheap filter an audit log rule's Operation condition gives the engine, or $null when the rule has none.
    .DESCRIPTION
        An anchor is an Operation condition using eq or in, or like with at least three characters of plain text. Every
        audit log rule needs one: it lets Get-CIPPAuditLogContent skip a blob without parsing it, and the engine run a
        record only through the rules its Operation can satisfy. A rule without one would have to be tested on every
        record of every blob, so the engine skips it. When a rule has several Operation conditions the first that
        anchors is used; a record the rule matches satisfies all of them.

        Returns Literals (the eq/in values, compared without case), Patterns (the like values as WildcardPatterns) and
        Needles: text, one of which a blob holds whenever a record in it can satisfy the anchor. A value gives
        '"Operation":"' followed by its plain leading characters, or, when it starts with a wildcard or other text,
        its longest plain run on its own. Plain means printable ASCII without a quote or backslash, which Microsoft's
        JSON writes as is. A value with no usable text means the condition cannot anchor the rule.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Conditions)

    $Plain = [regex]'[\x20\x21\x23-\x5B\x5D-\x7E]+'
    foreach ($Condition in @($Conditions)) {
        if ([string]$Condition.Property.label -ne 'Operation') { continue }
        $Operator = ([string]$Condition.Operator.value).ToLowerInvariant()
        if ($Operator -notin @('eq', 'in', 'like')) { continue }
        $Literals = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::InvariantCultureIgnoreCase)
        $Patterns = [System.Collections.Generic.List[System.Management.Automation.WildcardPattern]]::new()
        $Needles = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Anchored = $true
        $Values = @(foreach ($Value in @($Condition.Input.value)) { if (-not [string]::IsNullOrEmpty([string]$Value)) { [string]$Value } })
        if ($Values.Count -eq 0) { continue }
        foreach ($Value in $Values) {
            # The text a matching Operation must start with, and the plain runs it must contain anywhere.
            $Lead = if ($Operator -eq 'like') { ($Value -split '[*?\[]', 2)[0] } else { $Value }
            $LeadMatch = $Plain.Match($Lead)
            $Needle = if ($LeadMatch.Success -and $LeadMatch.Index -eq 0 -and ($LeadMatch.Length -ge 3 -or $LeadMatch.Length -eq $Value.Length)) {
                '"Operation":"' + $LeadMatch.Value
            } else {
                $Longest = ''
                foreach ($Run in ($Value -split '[*?\[\]]')) {
                    foreach ($Part in $Plain.Matches($Run)) { if ($Part.Length -gt $Longest.Length) { $Longest = $Part.Value } }
                }
                if ($Longest.Length -ge 3) { $Longest }
            }
            if (-not $Needle) { $Anchored = $false; break }
            [void]$Needles.Add($Needle)
            if ($Operator -eq 'like') { $Patterns.Add([System.Management.Automation.WildcardPattern]::new($Value, [System.Management.Automation.WildcardOptions]::IgnoreCase)) }
            else { [void]$Literals.Add($Value) }
        }
        if ($Anchored) {
            return [pscustomobject]@{ Literals = $Literals; Patterns = $Patterns.ToArray(); Needles = @($Needles) }
        }
    }
    $null
}
