function Remove-CIPPCloudBackupIndexHistory {
    <#
    .SYNOPSIS
        Removes an owner's index parts and snapshots that no point in time at or after -OlderThan needs.
    .DESCRIPTION
        Keeps the newest snapshot at or before -OlderThan and every file of its run or later. Without such a snapshot
        nothing is removed. Returns { Removed; SnapshotStamp }.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$OwnerPrefix,

        [Parameter(Mandatory = $true)]
        [datetime]$OlderThan
    )

    $Limit = $OlderThan.ToUniversalTime()
    $AllFiles = @(Get-CIPPCloudBackupIndexFile -Destination $Destination -OwnerPrefix $OwnerPrefix)
    $Keep = $null
    foreach ($File in $AllFiles) {
        if ($File.Snapshot -and $File.At -le $Limit) { $Keep = $File }
    }
    $Removed = 0
    if ($Keep) {
        foreach ($File in $AllFiles) {
            if ([string]::CompareOrdinal($File.RunStamp, $Keep.RunStamp) -ge 0) { break }
            if ($PSCmdlet.ShouldProcess($File.Key, 'Delete')) {
                Remove-CIPPCloudBackupObject -Destination $Destination -Key $File.Key -Confirm:$false
                $Removed++
            }
        }
    }
    [pscustomobject]@{ Removed = $Removed; SnapshotStamp = $Keep.RunStamp }
}
