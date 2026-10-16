function Get-CIPPCACoverageGuestCategory {
    param ($User)
    $Upn = [string]$User.userPrincipalName
    $IsExt = $Upn -like '*#EXT#*'
    $UserType = [string]$User.userType
    if ($UserType -eq 'Guest' -and $IsExt) { return 'b2bCollaborationGuest' }
    if ($UserType -eq 'Member' -and $IsExt) { return 'b2bCollaborationMember' }
    if ($UserType -eq 'Guest' -and -not $IsExt) { return 'internalGuest' }
    return $null
}
