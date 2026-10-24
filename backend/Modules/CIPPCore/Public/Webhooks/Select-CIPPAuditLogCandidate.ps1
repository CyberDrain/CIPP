function Select-CIPPAuditLogCandidate {
    <#
    .SYNOPSIS
        The records a Get-CIPPAuditLogPrefilter result keeps: those at least one rule could match.
    .DESCRIPTION
        A Graph search record is tested on its auditData, which is what Test-CIPPAuditLogRules matches; a feed record is
        the audit record itself. A rule that throws on a record keeps it. A $null prefilter keeps every record.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Prefilter,
        [object[]]$Records
    )

    foreach ($Record in $Records) {
        $View = $Record.auditData ?? $Record
        if ($null -eq $Prefilter -or $null -eq $View) { $Record; continue }
        $Rules = $Prefilter.Rules
        # A rule naming Operation values can only match a record with one of them, unless the engine's flattening of an
        # item named Operation replaces the record's own.
        if ($Prefilter.Index -and -not ($View.ExtendedProperties.Name -contains 'Operation' -or $View.DeviceProperties.Name -contains 'Operation' -or $View.parameters.Name -contains 'Operation' -or $View.ModifiedProperties.Name -contains 'Operation')) {
            $Operation = [string]$View.Operation
            if (-not $Prefilter.ByOperation.TryGetValue($Operation, [ref]$Rules)) {
                $Rules = @(foreach ($Entry in $Prefilter.Index) {
                        if (-not $Entry.Indexed -or $Entry.Literals.Contains($Operation) -or $Entry.Patterns.Where({ $_.IsMatch($Operation) }, 'First').Count -gt 0) { $Entry.Rule }
                    })
                $Prefilter.ByOperation[$Operation] = $Rules
            }
        }
        foreach ($Rule in $Rules) {
            $Kept = try { @($View).Where($Rule, 'First').Count -gt 0 } catch { $true }
            if ($Kept) { $Record; break }
        }
    }
}
