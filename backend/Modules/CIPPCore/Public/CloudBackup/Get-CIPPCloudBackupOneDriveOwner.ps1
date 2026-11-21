function Get-CIPPCloudBackupOneDriveOwner {
    <#
    .SYNOPSIS
        Lists the users in a tenant that have a OneDrive.
    .DESCRIPTION
        A user whose drive lookup fails for any reason other than not found is still listed, so a transient error
        shows up as a failed owner instead of silently dropping the user from the backup.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Users = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$select=id,displayName,userPrincipalName,userType&`$top=999" -tenantid $TenantFilter -asapp $true
    $UserById = @{}
    $Requests = foreach ($User in $Users) {
        if (-not $User.id -or $User.userType -eq 'Guest') { continue }
        $UserById[[string]$User.id] = $User
        @{ id = [string]$User.id; method = 'GET'; url = "users/$($User.id)/drive?`$select=id" }
    }
    if ($UserById.PSBase.Count -eq 0) { return @() }

    $Results = New-GraphBulkRequest -tenantid $TenantFilter -asapp $true -Version 'v1.0' -Requests @($Requests)
    foreach ($Result in $Results) {
        if ($Result.status -eq 404) { continue }
        $User = $UserById[[string]$Result.id]
        if (-not $User) { continue }
        [pscustomobject]@{
            OwnerId           = [string]$User.id
            OwnerType         = 'User'
            DisplayName       = $User.displayName
            UserId            = [string]$User.id
            UserPrincipalName = $User.userPrincipalName
            SiteUrl           = $null
        }
    }
}
