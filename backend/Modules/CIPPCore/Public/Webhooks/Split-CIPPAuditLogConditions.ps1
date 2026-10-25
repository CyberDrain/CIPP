function Split-CIPPAuditLogConditions {
    <#
    .SYNOPSIS
        Splits an audit log alert's conditions into its OR groups.
    .DESCRIPTION
        An alert matches a record when every condition of any one group matches it. A condition's Group number says which
        group it belongs to; a condition without one is in group 0, so an alert saved before groups existed is one group.
        A condition with a negative Group (-1) applies to every group, such as a user the whole alert leaves out, and is
        added to each of them. Returns one object per group, in group order, with its Group number and Conditions.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Conditions)

    $Shared = [System.Collections.Generic.List[object]]::new()
    $Groups = [System.Collections.Generic.SortedDictionary[int, System.Collections.Generic.List[object]]]::new()
    foreach ($Condition in @($Conditions)) {
        if ($null -eq $Condition) { continue }
        $Number = [int]($Condition.Group -as [int])
        if ($Number -lt 0) { $Shared.Add($Condition); continue }
        if (-not $Groups.ContainsKey($Number)) { $Groups[$Number] = [System.Collections.Generic.List[object]]::new() }
        $Groups[$Number].Add($Condition)
    }
    if ($Groups.Count -eq 0 -and $Shared.Count -gt 0) { $Groups[0] = [System.Collections.Generic.List[object]]::new() }
    foreach ($Entry in $Groups.GetEnumerator()) {
        [pscustomobject]@{ Group = $Entry.Key; Conditions = @($Entry.Value) + @($Shared) }
    }
}
