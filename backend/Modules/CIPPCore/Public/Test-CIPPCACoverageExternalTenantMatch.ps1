function Test-CIPPCACoverageExternalTenantMatch {
    param (
        $User,
        $ExternalTenants
    )
    if ($null -eq $ExternalTenants) { return $true }
    $Kind = [string]$ExternalTenants.membershipKind
    if ([string]::IsNullOrWhiteSpace($Kind) -or $Kind -eq 'all') { return $true }
    if ($Kind -ne 'enumerated') { return $true }

    $Allowed = @($ExternalTenants.members | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($Allowed.Count -eq 0) { return $false }

    $HomeTenantId = Get-CIPPCACoverageGuestHomeTenantId -User $User
    if (-not $HomeTenantId) { return $false }
    return ($Allowed -contains $HomeTenantId)
}
