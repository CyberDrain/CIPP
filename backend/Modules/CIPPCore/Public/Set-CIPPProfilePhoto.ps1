function Set-CIPPProfilePhoto {
    <#
    .NOTES
        Permission: Graph | PUT /groups/{id}/photo/$value | Delegated | ProfilePhoto.ReadWrite.All | User.ReadWrite, User.ReadWrite.All
        Permission: Graph | PUT /teams/{id}/photo/$value | Delegated | User.ReadWrite | User.ReadWrite.All
        Permission: Graph | PUT /users/{id}/photo/$value | Delegated | User.ReadWrite | User.ReadWrite.All
    #>
    [CmdletBinding()]
    param(
        $TenantFilter,
        $id,
        [ValidateSet('users', 'groups', 'teams')]
        $type = 'users',
        $ContentType = 'image/png',
        $PhotoBase64,
        $Headers
    )
    try {
        $PhotoBytes = [Convert]::FromBase64String($PhotoBase64)
        New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/$type/$id/photo/`$value" -tenantid $TenantFilter -type PUT -body $PhotoBytes -ContentType $ContentType
        "Successfully set profile photo for $id"
        Write-LogMessage -headers $Headers -API 'Set-CIPPUserProfilePhoto' -message "Successfully set profile photo for $id" -Sev 'Info' -tenant $TenantFilter
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        "Failed to set profile photo for $id. Error: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API 'Set-CIPPUserProfilePhoto' -message "Failed to set profile photo for $id. Error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -tenant $TenantFilter -LogData $ErrorMessage
    }
}
