function Get-CIPPCACoverageGuestHomeTenantId {
    param ($User)
    foreach ($Identity in @($User.identities)) {
        $Issuer = [string]$Identity.issuer
        if ($Issuer -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { return $Issuer }
    }
    return $null
}
