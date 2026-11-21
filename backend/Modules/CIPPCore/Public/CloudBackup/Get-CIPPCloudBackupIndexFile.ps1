function Get-CIPPCloudBackupIndexFile {
    <#
    .SYNOPSIS
        Lists an owner's index parts and snapshots as { Key; RunStamp; At; Part; Snapshot }, oldest first.
    .DESCRIPTION
        Within one RunStamp the snapshot sorts before that run's parts, which is the order they are replayed in.
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

    $Prefix = "$($OwnerPrefix)index/"
    $Files = foreach ($Object in @(Get-CIPPCloudBackupObjectList -Destination $Destination -Prefix $Prefix)) {
        $Name = "$($Object.Key)"
        if ($Name.StartsWith($Prefix, [System.StringComparison]::Ordinal)) { $Name = $Name.Substring($Prefix.Length) }
        if ($Name -match '^snapshot-(\d{8}T\d{6}Z)\.jsonl\.gz(\.enc)?$') {
            $Stamp = $Matches[1]
            $Part = -1
            $Snapshot = $true
        } elseif ($Name -match '^(\d{8}T\d{6}Z)-(\d+)\.jsonl\.gz(\.enc)?$') {
            $Stamp = $Matches[1]
            $Part = [int]$Matches[2]
            $Snapshot = $false
        } else {
            continue
        }
        [pscustomobject]@{
            Key      = "$Prefix$Name"
            RunStamp = $Stamp
            At       = [datetime]::ParseExact($Stamp, "yyyyMMdd'T'HHmmss'Z'", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal')
            Part     = $Part
            Snapshot = $Snapshot
        }
    }
    @($Files | Sort-Object -Property @{ Expression = 'RunStamp' }, @{ Expression = 'Snapshot'; Descending = $true }, @{ Expression = 'Part' })
}
