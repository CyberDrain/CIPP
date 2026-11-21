function Unprotect-CIPPCloudBackupStreamBlock {
    <#
    .SYNOPSIS
        Decrypts the next piece of a CIPPENC2 stream, writes every verified chunk it completes to -OutputStream and returns the number of bytes written.
    .DESCRIPTION
        -Decryptor is a hashtable this function keeps its state in: start with @{} and pass the same one for every
        piece, in order. Pieces may split the stream anywhere; pass -Final with the last one (which may be empty).
        For a range, set FirstChunk in -Decryptor and feed the 100-byte header followed by the frames from that chunk on.
        Every frame but the last is exactly chunk size + 16 bytes, so a full frame is never the final one. On a throw
        the output already holds the verified chunks before the damage, so callers must discard it.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Decryptor,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Buffer,

        [ValidateRange(0, [int]::MaxValue)]
        [int]$Offset = 0,

        [ValidateRange(-1, [int]::MaxValue)]
        [int]$Count = -1,

        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$OutputStream,

        [switch]$Final,

        [hashtable]$KeyCache
    )

    if ($Count -lt 0) { $Count = $Buffer.Length - $Offset }
    if ($Offset + $Count -gt $Buffer.Length) {
        throw [System.ArgumentException]::new('The offset and count are outside the buffer.')
    }
    $Position = $Offset
    $End = $Offset + $Count
    $Written = [long]0

    if ($Decryptor.Done) {
        if ($Count -gt 0) { throw $Decryptor.Damaged }
        return $Written
    }

    try {
        if (-not $Decryptor.DataKey) {
            if (-not $Decryptor.Header) {
                $Decryptor.Header = [byte[]]::new(100)
                $Decryptor.HeaderLength = 0
            }
            $Take = [Math]::Min(100 - $Decryptor.HeaderLength, $End - $Position)
            [System.Array]::Copy($Buffer, $Position, $Decryptor.Header, $Decryptor.HeaderLength, $Take)
            $Decryptor.HeaderLength += $Take
            $Position += $Take
            if ($Decryptor.HeaderLength -lt 100) {
                if ($Final) { throw [System.ArgumentException]::new('The data is not in the CIPP cloud backup streaming encryption format.') }
                return $Written
            }

            $Header = $Decryptor.Header
            if ([System.Text.Encoding]::ASCII.GetString($Header, 0, 8) -ne 'CIPPENC2') {
                throw [System.ArgumentException]::new('The data is not in the CIPP cloud backup streaming encryption format.')
            }
            $ChunkSize = ([int]$Header[24] -shl 24) -bor ([int]$Header[25] -shl 16) -bor ([int]$Header[26] -shl 8) -bor [int]$Header[27]
            if ($ChunkSize -lt 1 -or $ChunkSize -gt 64MB) {
                throw [System.ArgumentException]::new('The data is not in the CIPP cloud backup streaming encryption format.')
            }

            $KeyIdBytes = [byte[]]::new(16)
            [System.Array]::Copy($Header, 8, $KeyIdBytes, 0, 16)
            $KeyId = [guid]::new($KeyIdBytes)
            $Decryptor.Damaged = "The backup data could not be decrypted with key $($KeyId): it has been changed or is damaged."
            $Decryptor.Incomplete = "The backup data encrypted with key $($KeyId) is incomplete: it ends before its last chunk."
            $CacheKey = $KeyId.ToString()
            if ($null -ne $KeyCache -and $KeyCache.ContainsKey($CacheKey)) {
                $Key = ([byte[]]$KeyCache[$CacheKey]).Clone()
            } else {
                $Key = Get-CIPPCloudBackupKey -KeyId $KeyId
                if ($null -ne $KeyCache) { $KeyCache[$CacheKey] = $Key.Clone() }
            }

            $WrapData = [byte[]]::new(28)
            $WrapNonce = [byte[]]::new(12)
            $WrappedKey = [byte[]]::new(32)
            $WrapTag = [byte[]]::new(16)
            [System.Array]::Copy($Header, 0, $WrapData, 0, 28)
            [System.Array]::Copy($Header, 28, $WrapNonce, 0, 12)
            [System.Array]::Copy($Header, 40, $WrappedKey, 0, 32)
            [System.Array]::Copy($Header, 72, $WrapTag, 0, 16)
            $DataKey = [byte[]]::new(32)
            $WrapCipher = [System.Security.Cryptography.AesGcm]::new($Key, 16)
            try {
                $WrapCipher.Decrypt($WrapNonce, $WrappedKey, $WrapTag, $DataKey, $WrapData)
            } catch [System.Security.Cryptography.CryptographicException] {
                throw $Decryptor.Damaged
            } finally {
                $WrapCipher.Dispose()
                [System.Array]::Clear($Key, 0, $Key.Length)
            }

            $Associated = [byte[]]::new(109)
            [System.Array]::Copy($Header, 0, $Associated, 0, 100)
            $Decryptor.DataKey = $DataKey
            $Decryptor.Associated = $Associated
            $Decryptor.Frame = [byte[]]::new($ChunkSize + 16)
            $Decryptor.FrameLength = 0
            $Decryptor.Index = [uint64]$(if ($Decryptor.FirstChunk) { $Decryptor.FirstChunk } else { 0 })
        }

        $Frame = $Decryptor.Frame
        $Associated = $Decryptor.Associated
        while ($true) {
            $Take = [Math]::Min($Frame.Length - $Decryptor.FrameLength, $End - $Position)
            if ($Take -gt 0) {
                [System.Array]::Copy($Buffer, $Position, $Frame, $Decryptor.FrameLength, $Take)
                $Decryptor.FrameLength += $Take
                $Position += $Take
            }
            $Full = $Decryptor.FrameLength -eq $Frame.Length
            $Last = -not $Full -and $Final -and $Position -ge $End
            if (-not $Full -and -not $Last) { break }
            if ($Decryptor.FrameLength -lt 16) { throw $Decryptor.Incomplete }

            $Index = [uint64]$Decryptor.Index
            $PlainLength = $Decryptor.FrameLength - 16
            $Nonce = [byte[]]::new(12)
            [System.Array]::Copy($Decryptor.Header, 88, $Nonce, 0, 12)
            for ($i = 0; $i -lt 8; $i++) {
                $IndexByte = [byte](($Index -shr (8 * (7 - $i))) -band 0xFF)
                $Nonce[4 + $i] = $Nonce[4 + $i] -bxor $IndexByte
                $Associated[100 + $i] = $IndexByte
            }
            $Associated[108] = [byte]$(if ($Last) { 1 } else { 0 })

            $Ciphertext = [byte[]]::new($PlainLength)
            $Tag = [byte[]]::new(16)
            [System.Array]::Copy($Frame, 0, $Ciphertext, 0, $PlainLength)
            [System.Array]::Copy($Frame, $PlainLength, $Tag, 0, 16)
            $Plain = [byte[]]::new($PlainLength)
            $DataCipher = [System.Security.Cryptography.AesGcm]::new($Decryptor.DataKey, 16)
            try {
                $DataCipher.Decrypt($Nonce, $Ciphertext, $Tag, $Plain, $Associated)
            } catch [System.Security.Cryptography.CryptographicException] {
                throw $Decryptor.Damaged
            } finally {
                $DataCipher.Dispose()
            }
            $OutputStream.Write($Plain, 0, $PlainLength)
            $Written += $PlainLength
            $Decryptor.Index = $Index + 1
            $Decryptor.FrameLength = 0

            if ($Last) {
                $Decryptor.Done = $true
                [System.Array]::Clear($Decryptor.DataKey, 0, $Decryptor.DataKey.Length)
                $Decryptor.Frame = $null
                break
            }
        }
    } catch {
        if ($Decryptor.DataKey) { [System.Array]::Clear($Decryptor.DataKey, 0, $Decryptor.DataKey.Length) }
        $Decryptor.Done = $true
        if (-not $Decryptor.Damaged) { $Decryptor.Damaged = 'The backup data has been changed or is damaged.' }
        throw
    }
    return $Written
}
