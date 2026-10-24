function Get-CIPPAuditLogFeedWindow {
    <#
    .SYNOPSIS
        The range of a feed one round reads: from the cursor, at most 3 hours, never more than 6 hours back.
    .DESCRIPTION
        A new cursor starts an hour back. A cursor further back than 6 hours starts at 6 hours and Skipped says from
        where, so the caller can say what was not read. The range ends 5 minutes ago at the latest, since a listing can
        still miss blobs published in the last few minutes. Returns $null when there is nothing to read yet.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($LastEndUtc, [datetime]$Now = [datetime]::UtcNow)

    $Now = $Now.ToUniversalTime()
    $End = $Now.AddMinutes(-5)
    $Floor = $Now.AddHours(-6)
    $Start = if ($LastEndUtc) { ([datetimeoffset]$LastEndUtc).UtcDateTime } else { $End.AddHours(-1) }
    $Skipped = $null
    if ($Start -lt $Floor) { $Skipped = $Start; $Start = $Floor }
    $Stop = if ($Start.AddHours(3) -lt $End) { $Start.AddHours(3) } else { $End }
    if ($Start -ge $Stop) { return $null }
    [pscustomobject]@{ Start = $Start; End = $Stop; Skipped = $Skipped }
}
