function Read-CIPPCloudBackupObjectPart {
    <#
    .SYNOPSIS
        Reads one decrypted part of a stored cloud backup object, for downloads that are sent in parts.
    .DESCRIPTION
        Returns { Body (byte[]); Part; Parts; Size; ContentType }, or $null when the object or version does not exist.
        Size is the decrypted size of the whole object and Parts the number of parts of about -PartSize bytes it is
        split into. Only the stored bytes of the requested part are downloaded: CIPPENC2 parts are whole chunks, so they
        are decrypted on their own. CIPPENC1 objects are small and decrypted whole.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Destination,

        [Parameter(Mandatory = $true)]
        [string]$Key,

        [string]$VersionId,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Part = 0,

        [ValidateRange(1, 256MB)]
        [int]$PartSize = 16MB
    )

    $Source = @{ Destination = $Destination; Key = $Key }
    if ($VersionId) { $Source.VersionId = $VersionId }
    $Head = [System.IO.MemoryStream]::new()
    $Encrypted = $null
    $Output = $null
    try {
        $Info = Receive-CIPPCloudBackupObjectStream @Source -OutStream $Head -Offset 0 -Length 100
        if (-not $Info) { return $null }
        $Stored = [int64]$Info.Bytes
        $HeadBytes = $Head.ToArray()
        $Magic = if ($HeadBytes.Length -ge 8) { [System.Text.Encoding]::ASCII.GetString($HeadBytes, 0, 8) } else { '' }

        if ($Magic -eq 'CIPPENC2') {
            if ($HeadBytes.Length -lt 100 -or $Stored -lt 116) { throw "The backup data of '$Key' is incomplete." }
            $ChunkSize = ([int]$HeadBytes[24] -shl 24) -bor ([int]$HeadBytes[25] -shl 16) -bor ([int]$HeadBytes[26] -shl 8) -bor [int]$HeadBytes[27]
            if ($ChunkSize -lt 1 -or $ChunkSize -gt 64MB) { throw "The backup data of '$Key' is not in the CIPP cloud backup streaming encryption format." }
            $FrameSize = [int64]$ChunkSize + 16
            $Frames = [Math]::Floor(($Stored - 100) / $FrameSize) + 1
            $Size = $Stored - 100 - 16 * $Frames
            $PerPart = [Math]::Max(1, [Math]::Floor($PartSize / $ChunkSize))
            $Parts = [int][Math]::Max(1, [Math]::Ceiling(($Frames - 1) / $PerPart))
            if ($Part -ge $Parts) { throw [System.ArgumentException]::new("Part $Part does not exist; the download has $Parts part(s).") }
            $Last = $Part -eq $Parts - 1
            $FirstFrame = [int64]$Part * $PerPart
            $Count = if ($Last) { $Frames - $FirstFrame } else { $PerPart }
            $Offset = 100 + $FirstFrame * $FrameSize
            $Length = if ($Last) { $Stored - $Offset } else { $Count * $FrameSize }

            $Encrypted = [System.IO.MemoryStream]::new()
            $Encrypted.Write($HeadBytes, 0, 100)
            $null = Receive-CIPPCloudBackupObjectStream @Source -OutStream $Encrypted -Offset $Offset -Length $Length
            $Encrypted.Position = 0
            $Output = [System.IO.MemoryStream]::new()
            $Unprotect = @{ InputStream = $Encrypted; OutputStream = $Output; FirstChunk = [uint64]$FirstFrame }
            if (-not $Last) { $Unprotect.ChunkCount = [int]$Count }
            $null = Unprotect-CIPPCloudBackupStream @Unprotect
            $Body = $Output.ToArray()
        } elseif ($Magic -eq 'CIPPENC1') {
            if ($Stored -gt 64MB) { throw "The backup data of '$Key' is too large for its encryption format." }
            $Encrypted = [System.IO.MemoryStream]::new()
            $null = Receive-CIPPCloudBackupObjectStream @Source -OutStream $Encrypted
            $Plain = Unprotect-CIPPCloudBackupData -Bytes $Encrypted.ToArray()
            $Size = [int64]$Plain.Length
            $Parts = [int][Math]::Max(1, [Math]::Ceiling($Size / $PartSize))
            if ($Part -ge $Parts) { throw [System.ArgumentException]::new("Part $Part does not exist; the download has $Parts part(s).") }
            $Start = [int64]$Part * $PartSize
            $Body = [byte[]]::new([Math]::Min($PartSize, $Size - $Start))
            [System.Array]::Copy($Plain, $Start, $Body, 0, $Body.Length)
        } else {
            $Size = $Stored
            $Parts = [int][Math]::Max(1, [Math]::Ceiling($Size / $PartSize))
            if ($Part -ge $Parts) { throw [System.ArgumentException]::new("Part $Part does not exist; the download has $Parts part(s).") }
            $Output = [System.IO.MemoryStream]::new()
            if ($Size -gt 0) { $null = Receive-CIPPCloudBackupObjectStream @Source -OutStream $Output -Offset ([int64]$Part * $PartSize) -Length $PartSize }
            $Body = $Output.ToArray()
        }

        [pscustomobject]@{
            Body        = $Body
            Part        = $Part
            Parts       = $Parts
            Size        = [int64]$Size
            ContentType = $Info.ContentType
        }
    } finally {
        $Head.Dispose()
        if ($Encrypted) { $Encrypted.Dispose() }
        if ($Output) { $Output.Dispose() }
    }
}
