function New-CIPPGraphIdentityGrant {
    param(
        $Identity,
        [string]$PermissionSource,
        [string]$PermissionId,
        [array]$Roles,
        [array]$SharedWith,
        $LinkProps = $null
    )
    $principalType = 'Other'
    $principalObjectId = $null
    $principalUpn = $null
    $principalDisplayName = $null
    $principalLoginName = $null
    $principalEmail = $null
    $principalId = $null

    if ($Identity.user) {
        $principalType = 'User'
        $principalObjectId = $Identity.user.id
        $principalUpn = $Identity.user.userPrincipalName ?? $Identity.user.email
        $principalDisplayName = $Identity.user.displayName
        $principalEmail = $Identity.user.email ?? $Identity.user.userPrincipalName
        $principalId = [string]($Identity.user.id ?? $principalUpn)
    } elseif ($Identity.siteUser) {
        $principalType = 'User'
        $principalLoginName = $Identity.siteUser.loginName
        $principalDisplayName = $Identity.siteUser.displayName
        $principalEmail = $Identity.siteUser.email
        $principalUpn = if ($principalLoginName) { ($principalLoginName -split '\|')[-1] } else { $null }
        $principalId = [string]($principalLoginName ?? $principalEmail ?? $principalDisplayName)
    } elseif ($Identity.group) {
        $principalType = 'Security Group'
        $principalObjectId = $Identity.group.id
        $principalDisplayName = $Identity.group.displayName
        $principalEmail = $Identity.group.email
        $principalId = [string]$Identity.group.id
    } elseif ($Identity.siteGroup) {
        $principalType = 'SharePoint Group'
        $principalDisplayName = $Identity.siteGroup.displayName
        $principalId = [string]($Identity.siteGroup.id ?? $Identity.siteGroup.displayName)
    } elseif ($Identity.application) {
        $principalType = 'Application'
        $principalDisplayName = $Identity.application.displayName
        $principalId = [string]$Identity.application.id
    }

    $grant = [PSCustomObject]@{
        permissionSource     = $PermissionSource
        group                = $null
        principalId          = $principalId
        principalObjectId    = $principalObjectId
        principalUpn         = $principalUpn
        principalDisplayName = $principalDisplayName
        principalLoginName   = $principalLoginName
        principalEmail       = $principalEmail
        principalType        = $principalType
        permissionLevel      = $null
        roleDefinitionId     = $null
        roles                = @($Roles)
        isSiteAdmin          = $false
        isGuest              = (Test-CIPPGraphGuestIdentity -Identity $Identity)
        permissionId         = $PermissionId
        linkScope            = $null
        linkType             = $null
        linkUrl              = $null
        hasPassword          = $null
        expirationDateTime   = $null
        sharedWith           = @($SharedWith)
        libraryTitle         = $null
    }

    if ($LinkProps) {
        $grant.linkScope = $LinkProps.linkScope
        $grant.linkType = $LinkProps.linkType
        $grant.linkUrl = $LinkProps.linkUrl
        $grant.hasPassword = $LinkProps.hasPassword
        $grant.expirationDateTime = $LinkProps.expirationDateTime
        $grant.principalType = 'Link'
    }

    $grant
}
