function Resolve-CIPPCAPolicyNames {
    <#
    .SYNOPSIS
        Replaces display names in a CA policy's location, user and group conditions with object IDs.
    .DESCRIPTION
        Graph only accepts object IDs in conditions.locations and conditions.users, and rejects a
        display name with errors such as "1040: NamedLocation with id <name> does not exist in the
        directory". This resolves names against what the tenant already has, in place on -Policy:

        - include/excludeLocations: All, AllTrusted and GUIDs pass through; a name is matched by exact
          displayName against the tenant's named locations.
        - include/excludeUsers and include/excludeGroups: All, None, GuestsOrExternalUsers and GUIDs
          pass through; a name is matched by exact displayName. Nothing is created.

        A name that matches nothing throws an ItemNotFoundException naming the value, so a raw name
        is never sent to Graph. Tenant lookups run only when a name is present; -NamedLocations,
        -Users and -Groups take already-fetched lists instead.
    .PARAMETER LocationsOnly
        Resolve only the location conditions. The template deploy path resolves users and groups
        itself, because it can create missing groups.
    .PARAMETER LocationNotFoundHint
        Sentence appended to the error for a named location that does not exist.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Policy,
        [Parameter(Mandatory = $true)]
        $TenantFilter,
        $NamedLocations = $null,
        $Users = $null,
        $Groups = $null,
        $PolicyName = $Policy.displayName,
        $LocationNotFoundHint = 'Create it in the tenant first or select an existing named location.',
        [switch]$LocationsOnly,
        $Headers,
        $APIName = 'Create CA Policy'
    )

    # A name not defined in LocationInfo refers to a location the tenant already has.
    $LocationSides = @('includeLocations', 'excludeLocations').Where({ @($Policy.conditions.locations.$_).Where({ $_ -and $_ -notin 'All', 'AllTrusted' -and -not (Test-IsGuid -String $_) }).Count -gt 0 })
    if ($LocationSides.Count -gt 0) {
        if ($null -eq $NamedLocations) {
            $NamedLocations = try {
                New-GraphGETRequest -uri 'https://graph.microsoft.com/beta/identity/conditionalAccess/namedLocations?$top=999' -tenantid $TenantFilter -asApp $true
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                throw "Failed to fetch named locations: $($ErrorMessage.NormalizedError)"
            }
        }
        $TenantLocationIds = @{}
        foreach ($TenantLocation in @($NamedLocations)) {
            if ($TenantLocation.displayName -and -not $TenantLocationIds.ContainsKey($TenantLocation.displayName)) { $TenantLocationIds[$TenantLocation.displayName] = $TenantLocation.id }
        }
        foreach ($Side in $LocationSides) {
            $Policy.conditions.locations.$Side = @(foreach ($Location in @($Policy.conditions.locations.$Side)) {
                    if (-not $Location -or $Location -in 'All', 'AllTrusted' -or (Test-IsGuid -String $Location)) { $Location; continue }
                    if (-not $TenantLocationIds.ContainsKey($Location)) {
                        throw [System.Management.Automation.ItemNotFoundException]::new("Named location '$Location' used by policy '$PolicyName' was not found in $TenantFilter. $LocationNotFoundHint")
                    }
                    $TenantLocationIds[$Location]
                })
        }
    }

    if ($LocationsOnly) { return }

    $UserSides = @('includeUsers', 'excludeUsers').Where({ @($Policy.conditions.users.$_).Where({ $_ -and $_ -notin 'All', 'None', 'GuestsOrExternalUsers' -and -not (Test-IsGuid -String $_) }).Count -gt 0 })
    $GroupSides = @('includeGroups', 'excludeGroups').Where({ @($Policy.conditions.users.$_).Where({ -not [string]::IsNullOrWhiteSpace($_) -and -not (Test-IsGuid -String $_) }).Count -gt 0 })
    if ($UserSides.Count -eq 0 -and $GroupSides.Count -eq 0) { return }

    $Requests = @(
        if ($UserSides.Count -gt 0 -and $null -eq $Users) { @{ url = 'users?$select=id,displayName&$top=999'; method = 'GET'; id = 'users' } }
        if ($GroupSides.Count -gt 0 -and $null -eq $Groups) { @{ url = 'groups?$select=id,displayName&$top=999'; method = 'GET'; id = 'groups' } }
    )
    if ($Requests.Count -gt 0) {
        try {
            $BulkResults = New-GraphBulkRequest -Requests $Requests -tenantid $TenantFilter -asapp $true
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            throw "Failed to fetch users and groups: $($ErrorMessage.NormalizedError)"
        }
        if ($null -eq $Users) { $Users = @(($BulkResults | Where-Object { $_.id -eq 'users' }).body.value) }
        if ($null -eq $Groups) { $Groups = @(($BulkResults | Where-Object { $_.id -eq 'groups' }).body.value) }
    }

    foreach ($Side in $UserSides) {
        $Policy.conditions.users.$Side = @(Convert-CIPPCAUserNameToId -UserNames $Policy.conditions.users.$Side -Users $Users -Strict $true -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName)
    }
    foreach ($Side in $GroupSides) {
        $Policy.conditions.users.$Side = @(Convert-CIPPCAGroupNameToId -GroupNames $Policy.conditions.users.$Side -Groups $Groups -CreateGroups $false -NotFoundHint 'Create the group first or select an existing group.' -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName)
    }
}
