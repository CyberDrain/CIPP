function Get-CIPPPerUserMFA {
    <#
    .NOTES
        Permission: Graph | GET /users | Delegated | User.ReadBasic.All | User.Read.All, User.ReadWrite.All, Directory.Read.All, Directory.ReadWrite.All
        Permission: Graph | GET /users/{id} | Delegated | User.ReadBasic.All | User.ReadWrite, User.Read.All, User.ReadWrite.All, Directory.Read.All, Directory.ReadWrite.All
    #>
    [CmdletBinding()]
    param(
        $TenantFilter,
        $UserId,
        $Headers,
        $AllUsers = $false
    )
    try {
        if ($AllUsers -eq $true) {
            $AllUsers = New-GraphGetRequest -Uri "https://graph.microsoft.com/v1.0/users?`$top=999&`$select=UserPrincipalName,Id,perUserMfaState" -tenantid $TenantFilter
            return $AllUsers
        } else {
            $MFAState = New-GraphGetRequest -Uri "https://graph.microsoft.com/v1.0/users/$($UserId)?`$select=UserPrincipalName,Id,perUserMfaState" -tenantid $TenantFilter
            return [PSCustomObject]@{
                PerUserMFAState   = $MFAState.perUserMfaState
                UserPrincipalName = $UserId
            }
        }
    } catch {
        $ErrorMessage = Get-NormalizedError -Message $_.Exception.Message
        throw "Failed to get MFA State for $UserId : $ErrorMessage"
    }
}
