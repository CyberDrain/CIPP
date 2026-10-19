# Returns $true when a SharePoint user entity is a guest/external identity.
function Test-CIPPSpoGuestUser {
    param($User)
    [bool]$User.IsShareByEmailGuestUser -or [bool]$User.IsEmailAuthenticationGuestUser -or
        ($User.LoginName -match '(?i)#ext#|urn%3aspo%3aguest')
}
