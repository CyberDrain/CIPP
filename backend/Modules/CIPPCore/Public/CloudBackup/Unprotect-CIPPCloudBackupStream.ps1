function Unprotect-CIPPCloudBackupStream {
    <#
    .SYNOPSIS
        Decrypts a CIPPENC2 stream into another stream, fetching the key named in its header, and returns the number of bytes written.
    .DESCRIPTION
        Each chunk is verified before it is written. On a throw the output already holds the verified chunks before the
        damage, so callers must discard it.
        -KeyCache (key id -> key bytes) avoids a secret read per object when decrypting many.
        For a range, the input is the 100-byte header followed by the frames from -FirstChunk on; with -ChunkCount it
        stops after that many frames.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$InputStream,

        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$OutputStream,

        [hashtable]$KeyCache,

        [uint64]$FirstChunk = 0,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$ChunkCount = 0
    )

    $Decryptor = @{ FirstChunk = $FirstChunk }
    $Buffer = [byte[]]::new(1MB)
    $Written = [long]0
    do {
        $Read = $InputStream.Read($Buffer, 0, $Buffer.Length)
        $Final = $Read -le 0
        if ($Final -and $ChunkCount -gt 0 -and $Decryptor.Index -and ($Decryptor.Index - $FirstChunk) -ge $ChunkCount -and -not $Decryptor.FrameLength) {
            break
        }
        $Written += Unprotect-CIPPCloudBackupStreamBlock -Decryptor $Decryptor -Buffer $Buffer -Count ([Math]::Max($Read, 0)) -OutputStream $OutputStream -Final:$Final -KeyCache $KeyCache
    } while (-not $Final)
    return $Written
}
