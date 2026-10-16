# Friendly display value for an identity, preferring email over display name.
function Get-CIPPIdentityLabel {
    param($Identity)
    $Identity.user.email ?? $Identity.user.userPrincipalName ?? $Identity.siteUser.email ?? $Identity.user.displayName ?? $Identity.siteUser.displayName ?? $Identity.group.email ?? $Identity.group.displayName ?? $Identity.siteGroup.displayName
}
