# Returns $true when an identity (link recipient or direct grant) is external to the tenant.
function Test-CIPPExternalIdentity {
    param($Identity, $InternalDomains)
    $LoginName = [string]($Identity.siteUser.loginName ?? $Identity.user.loginName ?? '')
    if ($LoginName -match '#ext#' -or $LoginName -match 'urn%3aspo%3aguest' -or $LoginName -match 'urn:spo:guest') { return $true }
    $Email = [string]($Identity.user.email ?? $Identity.user.userPrincipalName ?? $Identity.siteUser.email ?? '')
    if ($Email -match '#EXT#') { return $true }
    if ($Email -and $Email.Contains('@') -and $InternalDomains.Count -gt 0) {
        return -not $InternalDomains.Contains($Email.Split('@')[-1])
    }
    return $false
}
