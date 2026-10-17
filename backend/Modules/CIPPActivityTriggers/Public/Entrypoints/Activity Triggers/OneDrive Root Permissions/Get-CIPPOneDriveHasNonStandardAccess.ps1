function Get-CIPPOneDriveHasNonStandardAccess {
    param($Grants, $OwnerObjectId, $OwnerPrincipalName, $LibraryHasUniquePermissions, $CollectionStatus)
    if ($CollectionStatus -eq 'Skipped') { return $null }
    if ($LibraryHasUniquePermissions) { return $true }

    foreach ($Grant in $Grants) {
        if ($Grant.permissionSource -eq 'SiteAdmin' -and -not (Test-CIPPOneDriveOwnerPrincipal -Grant $Grant -OwnerObjectId $OwnerObjectId -OwnerPrincipalName $OwnerPrincipalName)) {
            return $true
        }
        if ($Grant.permissionSource -eq 'SiteRoleGroup' -and $Grant.group -in @('Members', 'Visitors')) {
            return $true
        }
        if ($Grant.permissionSource -eq 'SiteRoleGroup' -and $Grant.group -eq 'Owners' -and
            -not (Test-CIPPOneDriveOwnerPrincipal -Grant $Grant -OwnerObjectId $OwnerObjectId -OwnerPrincipalName $OwnerPrincipalName)) {
            return $true
        }
        if ($Grant.principalType -in @('Security Group', 'M365 Group', 'SharePoint Group')) {
            return $true
        }
        if ($Grant.isGuest) { return $true }
        if ($Grant.permissionSource -eq 'DriveRootLink') { return $true }
        if ($Grant.permissionSource -eq 'DriveRootGrant' -and
            -not (Test-CIPPOneDriveOwnerPrincipal -Grant $Grant -OwnerObjectId $OwnerObjectId -OwnerPrincipalName $OwnerPrincipalName)) {
            return $true
        }
        if ($Grant.permissionSource -in @('WebRoleAssignment', 'LibraryRoleAssignment') -and
            -not (Test-CIPPOneDriveOwnerPrincipal -Grant $Grant -OwnerObjectId $OwnerObjectId -OwnerPrincipalName $OwnerPrincipalName)) {
            return $true
        }
    }
    return $false
}
