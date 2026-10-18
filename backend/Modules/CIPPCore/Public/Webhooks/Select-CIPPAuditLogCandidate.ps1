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
        foreach ($Rule in $Prefilter.Rules) {
            $Kept = try { @($View).Where($Rule, 'First').Count -gt 0 } catch { $true }
            if ($Kept) { $Record; break }
        }
    }
}
