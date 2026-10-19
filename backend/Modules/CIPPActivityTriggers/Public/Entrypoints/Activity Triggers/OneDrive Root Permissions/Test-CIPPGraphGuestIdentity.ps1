function Test-CIPPGraphGuestIdentity {
    param($Identity)
    $LoginName = [string]($Identity.siteUser.loginName ?? $Identity.user.loginName ?? '')
    if ($LoginName -match '(?i)#ext#|urn%3aspo%3aguest|urn:spo:guest') { return $true }
    $Email = [string]($Identity.user.email ?? $Identity.user.userPrincipalName ?? $Identity.siteUser.email ?? '')
    $Email -match '(?i)#EXT#'
}
