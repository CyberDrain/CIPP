function Get-CIPPSpoUserUpn {
    param($User)
    if ($User.PrincipalType -eq 1 -and $User.LoginName) {
        return ($User.LoginName -split '\|')[-1]
    }
    $null
}
