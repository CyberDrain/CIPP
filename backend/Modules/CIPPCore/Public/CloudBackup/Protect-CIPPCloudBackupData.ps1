function Protect-CIPPCloudBackupData {
    <#
    .SYNOPSIS
        Encrypts backup data with a random per-object key wrapped by the policy key (AES-256-GCM on both layers).
    .DESCRIPTION
        Output: 'CIPPENC1' (8) | key id (16) | wrap nonce (12) | wrapped data key (32) | wrap tag (16) | data nonce (12) |
        data tag (16) | ciphertext. Bytes 0..23 are associated data for the data layer.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [byte[]]$Bytes,

        [Parameter(Mandatory = $true)]
        [string]$KeyId,

        [Parameter(Mandatory = $true)]
        [byte[]]$Key
    )

    $ParsedId = [guid]::Empty
    if (-not [guid]::TryParse($KeyId, [ref]$ParsedId)) {
        throw [System.ArgumentException]::new("'$KeyId' is not a valid key id.")
    }
    if ($Key.Length -ne 32) {
        throw [System.ArgumentException]::new('The encryption key must be 32 bytes.')
    }

    $Output = [byte[]]::new(112 + $Bytes.Length)
    $Magic = [System.Text.Encoding]::ASCII.GetBytes('CIPPENC1')
    [System.Array]::Copy($Magic, 0, $Output, 0, 8)
    [System.Array]::Copy($ParsedId.ToByteArray(), 0, $Output, 8, 16)
    $Header = [byte[]]::new(24)
    [System.Array]::Copy($Output, 0, $Header, 0, 24)

    $DataKey = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $WrapNonce = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
    $DataNonce = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
    $WrappedKey = [byte[]]::new(32)
    $WrapTag = [byte[]]::new(16)
    $DataTag = [byte[]]::new(16)
    $Ciphertext = [byte[]]::new($Bytes.Length)

    $WrapCipher = [System.Security.Cryptography.AesGcm]::new($Key, 16)
    $DataCipher = [System.Security.Cryptography.AesGcm]::new($DataKey, 16)
    try {
        $WrapCipher.Encrypt($WrapNonce, $DataKey, $WrappedKey, $WrapTag)
        $DataCipher.Encrypt($DataNonce, $Bytes, $Ciphertext, $DataTag, $Header)
    } finally {
        $WrapCipher.Dispose()
        $DataCipher.Dispose()
        [System.Array]::Clear($DataKey, 0, $DataKey.Length)
    }

    [System.Array]::Copy($WrapNonce, 0, $Output, 24, 12)
    [System.Array]::Copy($WrappedKey, 0, $Output, 36, 32)
    [System.Array]::Copy($WrapTag, 0, $Output, 68, 16)
    [System.Array]::Copy($DataNonce, 0, $Output, 84, 12)
    [System.Array]::Copy($DataTag, 0, $Output, 96, 16)
    [System.Array]::Copy($Ciphertext, 0, $Output, 112, $Ciphertext.Length)
    return , $Output
}
