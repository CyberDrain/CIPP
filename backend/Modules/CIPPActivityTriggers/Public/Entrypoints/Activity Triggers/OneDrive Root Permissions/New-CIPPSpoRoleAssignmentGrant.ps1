function New-CIPPSpoRoleAssignmentGrant {
    param($Member, $RoleBinding, [string]$PermissionSource, [string]$LibraryTitle = $null)
    $principalUpn = if ($Member.PrincipalType -eq 1 -and $Member.LoginName) {
        ($Member.LoginName -split '\|')[-1]
    } else { $null }
    [PSCustomObject]@{
        permissionSource     = $PermissionSource
        group                = $RoleBinding.Name
        principalId          = [string]$Member.Id
        principalObjectId    = $null
        principalUpn         = $principalUpn
        principalDisplayName = $Member.Title
        principalLoginName   = $Member.LoginName
        principalEmail       = $Member.Email
        principalType        = Get-CIPPSpoPrincipalType -Entity $Member
        permissionLevel      = $RoleBinding.Name
        roleDefinitionId     = $RoleBinding.Id
        roles                = @()
        isSiteAdmin          = $false
        isGuest              = (Test-CIPPSpoGuestUser -User $Member)
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
