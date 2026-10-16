function Expand-CIPPCACoverageGuestBlock {
    <#
    .NOTES
        Permission: Graph | GET /users | Application | User.Read.All | User.ReadWrite.All, Directory.Read.All, Directory.ReadWrite.All
    #>
    param (
        $GuestConfig,
        [hashtable]$Map,
        [string]$Type,
        [string]$Field,
        [string]$TenantFilter,
        [System.Collections.Generic.List[object]]$Unresolved
    )
    if ($null -eq $GuestConfig) { return }
    $TypesRaw = $GuestConfig.guestOrExternalUserTypes
    if ([string]::IsNullOrWhiteSpace($TypesRaw) -or $TypesRaw -eq 'none') { return }

    $SelectedTypes = @(
        $TypesRaw -split ',' |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $_ -ne 'none' -and $_ -ne 'unknownFutureValue' } |
            Select-Object -Unique
    )
    if ($SelectedTypes.Count -eq 0) { return }

    # These CA categories are not reliably enumerable from directory user objects.
    $NonEnumerableTypes = @(
        'b2bDirectConnectUser'
        'otherExternalUser'
        'serviceProvider'
    )
    foreach ($GuestType in $SelectedTypes) {
        if ($NonEnumerableTypes -contains $GuestType) {
            $Unresolved.Add([pscustomobject]@{
                    field = $Field
                    id    = $GuestType
                    error = 'This guest or external user type cannot be expanded from directory users'
                }) | Out-Null
        }
    }

    $EnumerableTypes = @(
        $SelectedTypes | Where-Object {
            $_ -in @('b2bCollaborationGuest', 'b2bCollaborationMember', 'internalGuest')
        }
    )
    if ($EnumerableTypes.Count -eq 0) { return }

    $Candidates = [System.Collections.Generic.List[object]]::new()
    try {
        if ($EnumerableTypes -contains 'b2bCollaborationGuest' -or $EnumerableTypes -contains 'internalGuest') {
            $GuestUsers = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$filter=userType eq 'Guest'&`$select=id,displayName,userPrincipalName,userType,identities&`$top=999" -tenantid $TenantFilter -AsApp $true)
            foreach ($Guest in $GuestUsers) { $Candidates.Add($Guest) | Out-Null }
        }
        if ($EnumerableTypes -contains 'b2bCollaborationMember') {
            # B2B collaboration members keep the #EXT# UPN pattern with userType Member.
            $MemberExtUsers = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users?`$count=true&`$filter=userType eq 'Member' and contains(userPrincipalName,'#EXT#')&`$select=id,displayName,userPrincipalName,userType,identities&`$top=999" -tenantid $TenantFilter -AsApp $true -ComplexFilter)
            foreach ($Member in $MemberExtUsers) { $Candidates.Add($Member) | Out-Null }
        }
    } catch {
        $Unresolved.Add([pscustomobject]@{ field = $Field; id = $TypesRaw; error = $_.Exception.Message }) | Out-Null
        return
    }

    $Seen = [System.Collections.Generic.HashSet[string]]::new()
    $Label = "Guest types: $TypesRaw"
    foreach ($Candidate in $Candidates) {
        if (-not $Candidate.id) { continue }
        if (-not $Seen.Add([string]$Candidate.id)) { continue }

        $Category = Get-CIPPCACoverageGuestCategory -User $Candidate
        if (-not $Category -or ($EnumerableTypes -notcontains $Category)) { continue }
        if (-not (Test-CIPPCACoverageExternalTenantMatch -User $Candidate -ExternalTenants $GuestConfig.externalTenants)) {
            continue
        }

        Add-CIPPCACoverageReason -Map $Map -UserId $Candidate.id -Reason (New-CIPPCACoverageReason -Type $Type -Token $TypesRaw -Label $Label)
    }
}
