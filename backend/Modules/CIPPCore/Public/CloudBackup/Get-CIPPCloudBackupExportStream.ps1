function Get-CIPPCloudBackupExportStream {
    <#
    .SYNOPSIS
        Downloads a stored cloud backup object (or one version of it) and writes its decrypted bytes to a stream.
    .DESCRIPTION
        Returns { Key; VersionId; Bytes; ContentType }, where Bytes is the decrypted length, or $null when the object or
        version does not exist. CIPPENC2 and CIPPENC1 data is decrypted; anything else is copied as stored. The stored
        bytes pass through -BufferStream (a seekable stream the caller reuses) or a temporary file deleted on return,
        so memory use does not grow with the object size.
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

        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$OutStream,

        [hashtable]$KeyCache,

        [System.IO.Stream]$BufferStream
    )

    $OwnBuffer = $null -eq $BufferStream
    if ($OwnBuffer) {
        $BufferStream = [System.IO.FileStream]::new([System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), "cipp-cb-$([guid]::NewGuid().ToString('N')).tmp"), [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None, 81920, [System.IO.FileOptions]::DeleteOnClose)
    }
    try {
        $BufferStream.SetLength(0)
        $Params = @{ Destination = $Destination; Key = $Key; OutStream = $BufferStream }
        if ($VersionId) { $Params.VersionId = $VersionId }
        $Received = Receive-CIPPCloudBackupObjectStream @Params
        if (-not $Received) { return $null }

        $BufferStream.Position = 0
        $Magic = [byte[]]::new(8)
        $MagicLength = 0
        while ($MagicLength -lt 8) {
            $Read = $BufferStream.Read($Magic, $MagicLength, 8 - $MagicLength)
            if ($Read -le 0) { break }
            $MagicLength += $Read
        }
        $Format = if ($MagicLength -eq 8) { [System.Text.Encoding]::ASCII.GetString($Magic) }
        $BufferStream.Position = 0

        if ($Format -eq 'CIPPENC2') {
            $Written = Unprotect-CIPPCloudBackupStream -InputStream $BufferStream -OutputStream $OutStream -KeyCache $KeyCache
        } elseif ($Format -eq 'CIPPENC1') {
            $Stored = [byte[]]::new($BufferStream.Length)
            $Filled = 0
            while ($Filled -lt $Stored.Length) {
                $Read = $BufferStream.Read($Stored, $Filled, $Stored.Length - $Filled)
                if ($Read -le 0) { break }
                $Filled += $Read
            }
            $Plain = Unprotect-CIPPCloudBackupData -Bytes $Stored
            $OutStream.Write($Plain, 0, $Plain.Length)
            $Written = [long]$Plain.Length
        } else {
            $BufferStream.CopyTo($OutStream, 1MB)
            $Written = [long]$BufferStream.Length
        }

        [pscustomobject]@{
            Key         = $Key
            VersionId   = $Received.VersionId
            Bytes       = [long]$Written
            ContentType = $Received.ContentType
        }
    } finally {
        if ($OwnBuffer) { $BufferStream.Dispose() }
    }
}
