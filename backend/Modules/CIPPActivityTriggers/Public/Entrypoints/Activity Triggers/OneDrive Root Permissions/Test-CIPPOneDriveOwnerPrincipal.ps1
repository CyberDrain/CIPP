# Compares a grant principal to the provisioned OneDrive owner (drive.owner).
function Test-CIPPOneDriveOwnerPrincipal {
    param($Grant, $OwnerObjectId, $OwnerPrincipalName)
    if ($OwnerObjectId -and $Grant.principalObjectId -and
        $Grant.principalObjectId -eq $OwnerObjectId) { return $true }
    if ($OwnerPrincipalName -and $Grant.principalUpn -and
        $Grant.principalUpn -ieq $OwnerPrincipalName) { return $true }
    if ($OwnerPrincipalName -and $Grant.principalLoginName -and
        ($Grant.principalLoginName -split '\|')[-1] -ieq $OwnerPrincipalName) { return $true }
    return $false
}
