function Read-CIPPCloudBackupStreamBlock {
    <#
    .SYNOPSIS
        Returns the next block of up to -Size bytes from a cloud backup stream reader, encrypting as CIPPENC2 when the reader has a key.
    .DESCRIPTION
        -Reader is a hashtable @{ Stream; KeyId; Key; ChunkSize } that this function keeps its position in, with the bytes read from Stream in SourceBytes. A block shorter
        than -Size means the stream has ended. CIPPENC2: 'CIPPENC2' (8) | key id (16) | chunk size uint32 BE (4) |
        wrap nonce (12) | wrapped data key (32) | wrap tag (16) | base nonce (12), then one frame per plaintext chunk:
        ciphertext | tag (16). Every chunk but the last holds exactly chunk size bytes; the last holds fewer (possibly 0).
        Chunk i uses nonce = base nonce with bytes 4..11 XOR i (uint64 BE) and associated data = header | i (uint64 BE) |
        final flag (1 byte). The data key is wrapped with associated data = header bytes 0..27.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Reader,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$Size
    )

    $Block = [byte[]]::new($Size)
    $Filled = 0
    if (-not $Reader.KeyId) {
        while ($Filled -lt $Size) {
            $Read = $Reader.Stream.Read($Block, $Filled, $Size - $Filled)
            if ($Read -le 0) { break }
            $Filled += $Read
            $Reader.SourceBytes += $Read
        }
    } else {
        while ($Filled -lt $Size) {
            if ($null -ne $Reader.Pending -and $Reader.PendingOffset -lt $Reader.Pending.Length) {
                $Count = [Math]::Min($Size - $Filled, $Reader.Pending.Length - $Reader.PendingOffset)
                [System.Array]::Copy($Reader.Pending, $Reader.PendingOffset, $Block, $Filled, $Count)
                $Reader.PendingOffset += $Count
                $Filled += $Count
                continue
            }
            if ($Reader.Done) { break }

            if (-not $Reader.Header) {
                $ParsedId = [guid]::Empty
                if (-not [guid]::TryParse([string]$Reader.KeyId, [ref]$ParsedId)) {
                    throw [System.ArgumentException]::new("'$($Reader.KeyId)' is not a valid key id.")
                }
                if ($Reader.Key.Length -ne 32) {
                    throw [System.ArgumentException]::new('The encryption key must be 32 bytes.')
                }
                $ChunkSize = if ($Reader.ChunkSize) { [int]$Reader.ChunkSize } else { 4MB }
                $Reader.ChunkSize = $ChunkSize

                $Header = [byte[]]::new(100)
                [System.Array]::Copy([System.Text.Encoding]::ASCII.GetBytes('CIPPENC2'), 0, $Header, 0, 8)
                [System.Array]::Copy($ParsedId.ToByteArray(), 0, $Header, 8, 16)
                $Header[24] = [byte](($ChunkSize -shr 24) -band 0xFF)
                $Header[25] = [byte](($ChunkSize -shr 16) -band 0xFF)
                $Header[26] = [byte](($ChunkSize -shr 8) -band 0xFF)
                $Header[27] = [byte]($ChunkSize -band 0xFF)
                $WrapData = [byte[]]::new(28)
                [System.Array]::Copy($Header, 0, $WrapData, 0, 28)

                $DataKey = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
                $WrapNonce = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
                $WrappedKey = [byte[]]::new(32)
                $WrapTag = [byte[]]::new(16)
                $WrapCipher = [System.Security.Cryptography.AesGcm]::new($Reader.Key, 16)
                try {
                    $WrapCipher.Encrypt($WrapNonce, $DataKey, $WrappedKey, $WrapTag, $WrapData)
                } finally {
                    $WrapCipher.Dispose()
                }
                [System.Array]::Copy($WrapNonce, 0, $Header, 28, 12)
                [System.Array]::Copy($WrappedKey, 0, $Header, 40, 32)
                [System.Array]::Copy($WrapTag, 0, $Header, 72, 16)
                [System.Array]::Copy([System.Security.Cryptography.RandomNumberGenerator]::GetBytes(12), 0, $Header, 88, 12)

                $Reader.Header = $Header
                $Reader.DataKey = $DataKey
                $Reader.Index = [uint64]0
                $Reader.Pending = $Header
                $Reader.PendingOffset = 0
                continue
            }

            $ChunkSize = [int]$Reader.ChunkSize
            $Plain = [byte[]]::new($ChunkSize)
            $PlainLength = 0
            while ($PlainLength -lt $ChunkSize) {
                $Read = $Reader.Stream.Read($Plain, $PlainLength, $ChunkSize - $PlainLength)
                if ($Read -le 0) { break }
                $PlainLength += $Read
                $Reader.SourceBytes += $Read
            }
            $Final = $PlainLength -lt $ChunkSize
            if ($Final) { [System.Array]::Resize([ref]$Plain, $PlainLength) }

            $Index = [uint64]$Reader.Index
            $Nonce = [byte[]]::new(12)
            [System.Array]::Copy($Reader.Header, 88, $Nonce, 0, 12)
            $Associated = [byte[]]::new(109)
            [System.Array]::Copy($Reader.Header, 0, $Associated, 0, 100)
            for ($i = 0; $i -lt 8; $i++) {
                $IndexByte = [byte](($Index -shr (8 * (7 - $i))) -band 0xFF)
                $Nonce[4 + $i] = $Nonce[4 + $i] -bxor $IndexByte
                $Associated[100 + $i] = $IndexByte
            }
            $Associated[108] = [byte]$(if ($Final) { 1 } else { 0 })

            $Frame = [byte[]]::new($PlainLength + 16)
            $Ciphertext = [byte[]]::new($PlainLength)
            $Tag = [byte[]]::new(16)
            $DataCipher = [System.Security.Cryptography.AesGcm]::new($Reader.DataKey, 16)
            try {
                $DataCipher.Encrypt($Nonce, $Plain, $Ciphertext, $Tag, $Associated)
            } finally {
                $DataCipher.Dispose()
            }
            [System.Array]::Copy($Ciphertext, 0, $Frame, 0, $PlainLength)
            [System.Array]::Copy($Tag, 0, $Frame, $PlainLength, 16)

            $Reader.Index = $Index + 1
            $Reader.Pending = $Frame
            $Reader.PendingOffset = 0
            if ($Final) {
                $Reader.Done = $true
                [System.Array]::Clear($Reader.DataKey, 0, $Reader.DataKey.Length)
            }
        }
    }

    if ($Filled -lt $Size) { [System.Array]::Resize([ref]$Block, $Filled) }
    return , $Block
}
