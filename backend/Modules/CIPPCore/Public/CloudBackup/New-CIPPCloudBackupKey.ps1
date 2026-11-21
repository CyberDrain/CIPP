function New-CIPPCloudBackupKey {
    <#
    .SYNOPSIS
        Creates a 256-bit cloud backup encryption key, stores it as secret CloudBackupKey-<keyId> and returns the key id.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $KeyId = [guid]::NewGuid().ToString()
    if (-not $PSCmdlet.ShouldProcess($KeyId, 'Create cloud backup key')) { return }

    $Key = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    try {
        Set-CIPPSecret -Name "CloudBackupKey-$KeyId" -Value ([System.Convert]::ToBase64String($Key))
    } finally {
        [System.Array]::Clear($Key, 0, $Key.Length)
    }
    return $KeyId
}
