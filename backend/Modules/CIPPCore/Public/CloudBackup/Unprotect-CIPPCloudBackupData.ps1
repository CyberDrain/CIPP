function Unprotect-CIPPCloudBackupData {
    <#
    .SYNOPSIS
        Decrypts data written by Protect-CIPPCloudBackupData, fetching the key named in its header.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    if ($Bytes.Length -lt 112 -or [System.Text.Encoding]::ASCII.GetString($Bytes, 0, 8) -ne 'CIPPENC1') {
        throw [System.ArgumentException]::new('The data is not in the CIPP cloud backup encryption format.')
    }

    $Header = [byte[]]::new(24)
    [System.Array]::Copy($Bytes, 0, $Header, 0, 24)
    $KeyIdBytes = [byte[]]::new(16)
    [System.Array]::Copy($Bytes, 8, $KeyIdBytes, 0, 16)
    $KeyId = [guid]::new($KeyIdBytes)
    $Key = Get-CIPPCloudBackupKey -KeyId $KeyId

    $WrapNonce = [byte[]]::new(12)
    $WrappedKey = [byte[]]::new(32)
    $WrapTag = [byte[]]::new(16)
    $DataNonce = [byte[]]::new(12)
    $DataTag = [byte[]]::new(16)
    $Ciphertext = [byte[]]::new($Bytes.Length - 112)
    [System.Array]::Copy($Bytes, 24, $WrapNonce, 0, 12)
    [System.Array]::Copy($Bytes, 36, $WrappedKey, 0, 32)
    [System.Array]::Copy($Bytes, 68, $WrapTag, 0, 16)
    [System.Array]::Copy($Bytes, 84, $DataNonce, 0, 12)
    [System.Array]::Copy($Bytes, 96, $DataTag, 0, 16)
    [System.Array]::Copy($Bytes, 112, $Ciphertext, 0, $Ciphertext.Length)

    $DataKey = [byte[]]::new(32)
    $Plaintext = [byte[]]::new($Ciphertext.Length)
    $WrapCipher = [System.Security.Cryptography.AesGcm]::new($Key, 16)
    try {
        $WrapCipher.Decrypt($WrapNonce, $WrappedKey, $WrapTag, $DataKey)
        $DataCipher = [System.Security.Cryptography.AesGcm]::new($DataKey, 16)
        try {
            $DataCipher.Decrypt($DataNonce, $Ciphertext, $DataTag, $Plaintext, $Header)
        } finally {
            $DataCipher.Dispose()
        }
    } catch [System.Security.Cryptography.CryptographicException] {
        throw "The backup data could not be decrypted with key $($KeyId): it has been changed or is damaged."
    } finally {
        $WrapCipher.Dispose()
        [System.Array]::Clear($DataKey, 0, $DataKey.Length)
        [System.Array]::Clear($Key, 0, $Key.Length)
    }
    return , $Plaintext
}
