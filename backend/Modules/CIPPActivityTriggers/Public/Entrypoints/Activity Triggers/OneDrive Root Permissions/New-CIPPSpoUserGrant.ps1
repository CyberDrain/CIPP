function New-CIPPSpoUserGrant {
    param(
        $User,
        [string]$PermissionSource,
        [string]$Group,
        $RoleBinding = $null,
        [bool]$IsSiteAdmin = $false,
        [string]$LibraryTitle = $null
    )
    [PSCustomObject]@{
        permissionSource     = $PermissionSource
        group                = $Group
        principalId          = [string]$User.Id
        principalObjectId    = $null
        principalUpn         = Get-CIPPSpoUserUpn -User $User
        principalDisplayName = $User.Title
        principalLoginName   = $User.LoginName
        principalEmail       = $User.Email
        principalType        = Get-CIPPSpoPrincipalType -Entity $User
        permissionLevel      = if ($RoleBinding) { $RoleBinding.Name } else { $null }
        roleDefinitionId     = if ($RoleBinding) { $RoleBinding.Id } else { $null }
        roles                = @()
        isSiteAdmin          = $IsSiteAdmin
        isGuest              = (Test-CIPPSpoGuestUser -User $User)
        permissionId         = $null
        linkScope            = $null
        linkType             = $null
        linkUrl              = $null
        hasPassword          = $null
        expirationDateTime   = $null
        sharedWith           = @()
        libraryTitle         = $LibraryTitle
    }
}
