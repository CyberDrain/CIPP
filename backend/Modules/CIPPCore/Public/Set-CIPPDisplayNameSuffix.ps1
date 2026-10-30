function Set-CIPPDisplayNameSuffix {
    [CmdletBinding()]
    param (
        $UserID,
        $DisplayName,
        $Suffix,
        $TenantFilter,
        $APIName = 'Set Display Name Suffix',
        $Headers
    )

    $Suffix = ([string]$Suffix).Trim()
    # A re-run sees the already-renamed user; appending again would double the suffix
    if (([string]$DisplayName).EndsWith(" $Suffix", [System.StringComparison]::OrdinalIgnoreCase)) {
        return "Display name of $UserID already ends with '$Suffix'"
    }
    $NewDisplayName = "$DisplayName $Suffix"

    try {
        $Body = ConvertTo-Json -InputObject @{ displayName = $NewDisplayName } -Compress
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)" -tenantid $TenantFilter -type PATCH -body $Body
        $Result = "Successfully changed display name of $UserID to '$NewDisplayName'"
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info' -tenant $TenantFilter
        return $Result
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to change display name of $UserID. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -message $Message -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
        throw $Message
    }
}
