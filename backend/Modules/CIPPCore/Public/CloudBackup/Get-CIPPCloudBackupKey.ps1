function Get-CIPPCloudBackupKey {
    <#
    .SYNOPSIS
        Returns the 32-byte cloud backup encryption key stored for a key id.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$KeyId
    )

    $ParsedId = [guid]::Empty
    if (-not [guid]::TryParse($KeyId, [ref]$ParsedId)) {
        throw [System.ArgumentException]::new("'$KeyId' is not a valid key id.")
    }
    $Encoded = Get-CIPPSecret -Name "CloudBackupKey-$ParsedId"
    if (-not $Encoded) {
        throw [System.Management.Automation.ItemNotFoundException]::new("Encryption key $ParsedId was not found.")
    }
    $Key = [System.Convert]::FromBase64String($Encoded)
    if ($Key.Length -ne 32) {
        throw "Encryption key $ParsedId is not a 256-bit key."
    }
    return , $Key
}
