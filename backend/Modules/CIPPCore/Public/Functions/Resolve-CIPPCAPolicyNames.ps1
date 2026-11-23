function Resolve-CIPPCAPolicyNames {
    <#
    .SYNOPSIS
        Replaces display names in a CA policy's location, user and group conditions with object IDs, in place.
    .DESCRIPTION
        Keywords (All, AllTrusted, None, GuestsOrExternalUsers) and GUIDs pass through. A name is matched by exact
        displayName; one that matches nothing throws an ItemNotFoundException naming it. Nothing is created.
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
        $PolicyName = $Policy.displayName,
        $LocationNotFoundHint = 'Create it in the tenant first or select an existing named location.',
        [switch]$LocationsOnly,
        $Headers,
        $APIName = 'Create CA Policy'
    )

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

    $Lookups = @(
        foreach ($Side in $UserSides) { foreach ($Name in $Policy.conditions.users.$Side) { if ($Name -notin 'All', 'None', 'GuestsOrExternalUsers' -and -not (Test-IsGuid -String $Name)) { @{ Kind = 'users'; Name = $Name } } } }
        foreach ($Side in $GroupSides) { foreach ($Name in $Policy.conditions.users.$Side) { if (-not [string]::IsNullOrWhiteSpace($Name) -and -not (Test-IsGuid -String $Name)) { @{ Kind = 'groups'; Name = $Name } } } }
    )
    $Requests = [System.Collections.Generic.List[hashtable]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new()
    foreach ($Lookup in $Lookups) {
        if (-not $Seen.Add("$($Lookup.Kind)|$($Lookup.Name)")) { continue }
        $Filter = [System.Uri]::EscapeDataString("displayName eq '$($Lookup.Name -replace "'", "''")'")
        $Requests.Add(@{ id = "$($Lookup.Kind)-$($Requests.Count)"; method = 'GET'; url = "$($Lookup.Kind)?`$filter=$Filter&`$select=id,displayName" })
    }
    try {
        $BulkResults = New-GraphBulkRequest -Requests @($Requests) -tenantid $TenantFilter -asapp $true
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        throw "Failed to look up users and groups: $($ErrorMessage.NormalizedError)"
    }
    $Users = [System.Collections.Generic.List[object]]::new()
    $Groups = [System.Collections.Generic.List[object]]::new()
    foreach ($Result in @($BulkResults)) {
        if ($Result.status -ge 400) { throw "Failed to look up users and groups: $($Result.body.error.message ?? "Graph returned status $($Result.status)")" }
        foreach ($Item in @($Result.body.value)) {
            if (-not $Item) { continue }
            if ($Result.id -like 'users-*') { $Users.Add($Item) } else { $Groups.Add($Item) }
        }
    }

    foreach ($Side in $UserSides) {
        $Policy.conditions.users.$Side = @(Convert-CIPPCAUserNameToId -UserNames $Policy.conditions.users.$Side -Users $Users -Strict $true -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName)
    }
    foreach ($Side in $GroupSides) {
        $Policy.conditions.users.$Side = @(Convert-CIPPCAGroupNameToId -GroupNames $Policy.conditions.users.$Side -Groups $Groups -CreateGroups $false -NotFoundHint 'Create the group first or select an existing group.' -TenantFilter $TenantFilter -Headers $Headers -APIName $APIName)
    }
}
