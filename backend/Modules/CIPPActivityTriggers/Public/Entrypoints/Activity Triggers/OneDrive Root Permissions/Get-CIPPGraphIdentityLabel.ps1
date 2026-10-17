function Get-CIPPGraphIdentityLabel {
    param($Identity)
    $Identity.user.email ?? $Identity.user.userPrincipalName ??
        $Identity.siteUser.email ?? $Identity.user.displayName ??
        $Identity.siteUser.displayName ?? $Identity.group.email ??
        $Identity.group.displayName ?? $Identity.siteGroup.displayName ??
        $Identity.application.displayName
}
