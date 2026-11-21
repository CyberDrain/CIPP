function Get-CIPPCloudBackupRecoveryPoint {
    <#
    .SYNOPSIS
        Lists the points in time an owner's backup can be browsed or restored at, as { RunStamp; At }, newest first.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$OwnerPrefix
    )

    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $Files = @(Get-CIPPCloudBackupIndexFile -Destination $Destination -OwnerPrefix $OwnerPrefix)
    for ($i = $Files.Count - 1; $i -ge 0; $i--) {
        if ($Seen.Add($Files[$i].RunStamp)) {
            [pscustomobject]@{ RunStamp = $Files[$i].RunStamp; At = $Files[$i].At }
        }
    }
}
