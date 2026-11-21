function Invoke-CIPPCloudBackupIndexCompaction {
    <#
    .SYNOPSIS
        Writes an index snapshot holding an owner's full item state as of its newest index part, when one is due.
    .DESCRIPTION
        A snapshot is due when at least -MinParts parts were written since the last snapshot, or the last snapshot (or,
        without one, the oldest part) is older than -MaxAgeDays. Deleted items are kept, marked d, unless they were
        deleted in a run before -DeletedBefore. Nothing is deleted. Returns { Compacted; SnapshotStamp; PartsMerged }.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$OwnerPrefix,

        [string]$KeyId,

        [byte[]]$Key,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$MinParts = 50,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxAgeDays = 7,

        [datetime]$DeletedBefore
    )

    $AllFiles = @(Get-CIPPCloudBackupIndexFile -Destination $Destination -OwnerPrefix $OwnerPrefix)
    $Snapshot = $null
    foreach ($File in $AllFiles) { if ($File.Snapshot) { $Snapshot = $File } }
    $NewParts = @(foreach ($File in $AllFiles) {
            if (-not $File.Snapshot -and (-not $Snapshot -or [string]::CompareOrdinal($File.RunStamp, $Snapshot.RunStamp) -gt 0)) { $File }
        })
    $NotDone = [pscustomobject]@{ Compacted = $false; SnapshotStamp = $Snapshot.RunStamp; PartsMerged = 0 }
    if ($NewParts.Count -eq 0) { return $NotDone }
    $Since = if ($Snapshot) { $Snapshot.At } else { $NewParts[0].At }
    if ($NewParts.Count -lt $MinParts -and $Since -ge [datetime]::UtcNow.AddDays(-$MaxAgeDays)) { return $NotDone }

    $Stamp = $NewParts[-1].RunStamp
    $Files = @(foreach ($File in $AllFiles) {
            if ($Snapshot) {
                if ([string]::CompareOrdinal($File.RunStamp, $Snapshot.RunStamp) -lt 0) { continue }
                if ($File.Snapshot -and $File -ne $Snapshot) { continue }
            }
            $File
        })
    $State = Read-CIPPCloudBackupIndexState -Destination $Destination -OwnerPrefix $OwnerPrefix -Files $Files
    $DropBefore = if ($PSBoundParameters.ContainsKey('DeletedBefore')) { $DeletedBefore.ToUniversalTime().ToString('yyyyMMddTHHmmssZ') } else { $null }

    $Kept = [System.Collections.Generic.List[int]]::new()
    for ($Slot = 0; $Slot -lt $State.Keys.Count; $Slot++) {
        if ($DropBefore -and $State.D[$Slot] -and [string]::CompareOrdinal($State.R[$Slot], $DropBefore) -lt 0) { continue }
        $Kept.Add($Slot)
    }
    $Order = [long[]]::new($Kept.Count)
    $OrderSlots = $Kept.ToArray()
    for ($i = 0; $i -lt $OrderSlots.Length; $i++) {
        $Order[$i] = ([long]$State.Src[$OrderSlots[$i]] -shl 32) -bor [long]$State.Line[$OrderSlots[$i]]
    }
    [System.Array]::Sort($Order, $OrderSlots)

    $Temp = [System.IO.FileStream]::new([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.IO.Path]::GetRandomFileName()), [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None, 81920, [System.IO.FileOptions]::DeleteOnClose)
    try {
        $Gzip = [System.IO.Compression.GZipStream]::new($Temp, [System.IO.Compression.CompressionLevel]::Optimal, $true)
        $Writer = [System.IO.StreamWriter]::new($Gzip, [System.Text.UTF8Encoding]::new($false))
        try {
            $Position = 0
            while ($Position -lt $Order.Length) {
                $Src = [int]($Order[$Position] -shr 32)
                $FromSnapshot = [bool]$State.Files[$Src].Snapshot
                $Reader = Open-CIPPCloudBackupIndexReader -Destination $Destination -Key $State.Files[$Src].Key
                try {
                    $LineNo = -1
                    while ($Position -lt $Order.Length -and [int]($Order[$Position] -shr 32) -eq $Src -and $null -ne ($Text = $Reader.ReadLine())) {
                        $LineNo++
                        if (($Order[$Position] -band 0xFFFFFFFFL) -ne $LineNo) { continue }
                        $Slot = $OrderSlots[$Position]
                        $Position++
                        if ($State.D[$Slot]) {
                            $Entry = [CIPP.CippJson]::ConvertFromJson($Text)
                            $Record = [ordered]@{ r = $State.R[$Slot]; k = $Entry.k; p = $Entry.p; n = $Entry.n; t = $Entry.t; s = $Entry.s; m = $Entry.m; v = $Entry.v; d = $true; x = $Entry.x }
                            $Writer.Write(([CIPP.CippJson]::ToJson($Record, 10) ?? (ConvertTo-Json -InputObject $Record -Depth 10 -Compress)))
                        } elseif ($FromSnapshot) {
                            $Writer.Write($Text)
                        } else {
                            $Writer.Write('{"r":"')
                            $Writer.Write($State.R[$Slot])
                            $Writer.Write('",')
                            $Writer.Write($Text.Substring(1))
                        }
                        $Writer.Write("`n")
                    }
                } finally {
                    $Reader.Dispose()
                }
                while ($Position -lt $Order.Length -and [int]($Order[$Position] -shr 32) -eq $Src) { $Position++ }
            }
        } finally {
            $Writer.Dispose()
        }
        $Temp.Position = 0
        $Params = @{
            Destination = $Destination
            Key         = "$($OwnerPrefix)index/snapshot-$Stamp.jsonl.gz"
            Stream      = $Temp
            ContentType = 'application/gzip'
        }
        if ($Key) {
            $Params.Key = "$($Params.Key).enc"
            $Params.KeyId = $KeyId
            $Params.EncryptionKey = $Key
        }
        $null = Send-CIPPCloudBackupObjectStream @Params
    } finally {
        $Temp.Dispose()
    }

    [pscustomobject]@{ Compacted = $true; SnapshotStamp = $Stamp; PartsMerged = $NewParts.Count }
}
