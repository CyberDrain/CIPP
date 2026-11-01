function Get-CIPPBaselineGlobalSecureAccessM365ProfileState {
    <#
    .SYNOPSIS
        Prepare hook for GlobalSecureAccessM365Profile: grades the Microsoft 365 traffic
        forwarding profile from the NetworkAccess cache.
    .DESCRIPTION
        The assignment model is the profile's own assignmentRules - AllMembership (all
        users) or EnumeratedMembership (users/groups/devices) - captured by the cache
        collector. The legacy enterprise-app surface (the profile app's assignment flag)
        is not graded: the Global Secure Access portal's User and device assignments
        blade does not read it. The expected state is conditional, like the packaged
        compliant-network standard's enforce variable: 'disabled' expresses an opinion on
        the profile state alone - links and assignment are left to the administrator -
        while 'enabled' also grades every policy link and the assignment. AllUsers grades
        the membership type; CustomGroups additionally grades that every configured group
        (resolved by display name through the Groups cache) holds an assignment,
        ADDITIVELY: assignments an administrator made by hand are never drift. A tenant
        that is not onboarded gets the onboarding prerequisite named instead of Graph's
        403, and a missing default profile (onboarding settles asynchronously and the
        profile cannot be created via the API) reports No Data.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter)

    $V = $Item.Variables
    if ($V -is [System.Collections.IDictionary]) { $V = [PSCustomObject]$V }
    $ProfileState = "$($V.profileState)"
    if (-not $ProfileState) { $ProfileState = 'enabled' }
    $AssignTo = "$($V.assignTo)"
    if (-not $AssignTo) { $AssignTo = 'AllUsers' }
    $GroupRefs = @($V.assignedGroups | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ })

    if ($ProfileState -notin @('enabled', 'disabled')) {
        return @{ Current = $null; ConfigError = $true; NoDataReason = "profileState must be 'enabled' or 'disabled', not '$ProfileState'." }
    }
    if ($AssignTo -notin @('AllUsers', 'CustomGroups')) {
        return @{ Current = $null; ConfigError = $true; NoDataReason = "assignTo must be 'AllUsers' or 'CustomGroups', not '$AssignTo'." }
    }
    if ($ProfileState -eq 'enabled' -and $AssignTo -eq 'CustomGroups' -and $GroupRefs.Count -eq 0) {
        return @{ Current = $null; ConfigError = $true; NoDataReason = 'CustomGroups is selected but no groups are configured - a scoped profile with no assigned groups gives no user the profile.' }
    }

    $State = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'NetworkAccess' | Where-Object { $_ }) | Select-Object -First 1
    if (-not $State) { return @{ Current = $null } }
    if ($State.onboarded -ne $true) {
        return @{ Current = $null; NoDataReason = 'the tenant is not onboarded to Global Secure Access - enable the "Onboard Global Secure Access" standard first' }
    }
    $TrafficProfile = @($State.profiles | Where-Object { $_.trafficForwardingType -eq 'm365' -and $_.isCustomProfile -ne $true }) | Select-Object -First 1
    if (-not $TrafficProfile) {
        return @{ Current = $null; NoDataReason = 'the Microsoft 365 traffic forwarding profile has not been created yet - onboarding may still be settling; run the standard again in a few minutes' }
    }

    $Links = @($TrafficProfile.policies | Where-Object { $_ })
    $AssignmentType = "$($TrafficProfile.assignmentRules.assignments.'@odata.type')"
    $Current = [ordered]@{
        profileState       = "$($TrafficProfile.state)"
        policyLinksEnabled = $Links.Count -gt 0 -and @($Links | Where-Object { $_.state -ne 'enabled' }).Count -eq 0
        assignedToAllUsers = $AssignmentType -like '*forwardingProfileAssignmentsAllMembership'
    }
    $Expected = [ordered]@{
        profileState = $ProfileState
    }
    if ($ProfileState -eq 'enabled') {
        $Expected.policyLinksEnabled = $true
        if ($AssignTo -eq 'AllUsers') {
            $Expected.assignedToAllUsers = $true
        } else {
            $Expected.assignedToAllUsers = $false
            $Expected.configuredGroupsAssigned = $true
            # Additive: only the configured groups are graded; assignments an
            # administrator made by hand are never drift.
            $AssignedIds = @($TrafficProfile.assignmentRules.assignments.groups | Where-Object { $_ } | ForEach-Object { "$($_.id)" })
            $Groups = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups')
            $Current.configuredGroupsAssigned = @($GroupRefs | ForEach-Object {
                    $Ref = $_
                    $Match = $Groups | Where-Object { $_.displayName -eq $Ref } | Select-Object -First 1
                    ($null -ne $Match) -and ($AssignedIds -contains $Match.id)
                }) -notcontains $false
        }
    }
    @{ Expected = [PSCustomObject]$Expected; Current = [PSCustomObject]$Current }
}
