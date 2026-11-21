function Test-CIPPCloudBackupPolicyScope {
    <#
    .SYNOPSIS
        True when every target of a cloud backup policy is within the caller's allowed tenants.
    .DESCRIPTION
        A restricted caller (AllowedTenants without 'AllTenants') can only reach policies that name individual tenants
        they can access; AllTenants and tenant group targets reach beyond any fixed tenant list.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Tenants,
        $AllowedTenants
    )

    $Allowed = @($AllowedTenants)
    if ($Allowed -contains 'AllTenants') { return $true }
    foreach ($Entry in @($Tenants)) {
        if ($Entry.type -ne 'Tenant' -or $Allowed -notcontains $Entry.customerId) { return $false }
    }
    $true
}
