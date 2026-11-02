function Get-CIPPBaselineForwardingProfileState {
    <#
    .SYNOPSIS
        Shared grading core for the Global Secure Access traffic forwarding profile
        standards (Microsoft 365, Internet).
    .DESCRIPTION
        The assignment model is the profile's own assignmentRules - AllMembership (all
        users and devices) or EnumeratedMembership (users/groups/devices) - captured by
        the cache collector; the legacy enterprise-app surface is not graded. The
        assignTo picker follows the Intune template convention: DoNotAssign (an enabled
        profile nobody holds), AllDevicesAndUsers (AllMembership) or customGroup (the
        configured group names, wildcards allowed, resolved through the Groups cache).
        The expected state is conditional: 'disabled' expresses an opinion on the profile
        state alone. Assignments an administrator made by hand are never drift - except
        under DoNotAssign, where any assignment means somebody holds the profile. A
        tenant that is not onboarded gets the onboarding prerequisite named, and a
        missing profile reports No Data. A profile with no policy links grades its links
        as enabled: some default profiles carry none until their policies are set up.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Item, $TenantFilter, [string]$TrafficType, [string]$ProfileLabel)

    $V = $Item.Variables
    if ($V -is [System.Collections.IDictionary]) { $V = [PSCustomObject]$V }
    $ProfileState = "$($V.profileState)"
    if (-not $ProfileState) { $ProfileState = 'enabled' }
    $AssignTo = "$($V.assignTo)"
    if (-not $AssignTo) { $AssignTo = 'AllDevicesAndUsers' }
    $GroupRefs = @("$($V.customGroup)" -split ',' | ForEach-Object { "$_".Trim() } | Where-Object { $_ })

    if ($ProfileState -notin @('enabled', 'disabled')) {
        return @{ Current = $null; ConfigError = $true; NoDataReason = "profileState must be 'enabled' or 'disabled', not '$ProfileState'." }
    }
    if ($AssignTo -notin @('DoNotAssign', 'AllDevicesAndUsers', 'customGroup')) {
        return @{ Current = $null; ConfigError = $true; NoDataReason = "assignTo must be 'DoNotAssign', 'AllDevicesAndUsers' or 'customGroup', not '$AssignTo'." }
    }
    if ($ProfileState -eq 'enabled' -and $AssignTo -eq 'customGroup' -and $GroupRefs.Count -eq 0) {
        return @{ Current = $null; ConfigError = $true; NoDataReason = 'customGroup is selected but no group name is configured - a scoped profile with no assigned groups gives no user the profile.' }
    }

    $State = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'NetworkAccess' | Where-Object { $_ }) | Select-Object -First 1
    if (-not $State) { return @{ Current = $null } }
    if ($State.onboarded -ne $true) {
        return @{ Current = $null; NoDataReason = 'the tenant is not onboarded to Global Secure Access - enable the "Onboard Global Secure Access" standard first' }
    }
    $TrafficProfile = @($State.profiles | Where-Object { $_.trafficForwardingType -eq $TrafficType -and $_.isCustomProfile -ne $true }) | Select-Object -First 1
    if (-not $TrafficProfile) {
        return @{ Current = $null; NoDataReason = "the $ProfileLabel traffic forwarding profile has not been created yet - onboarding may still be settling; run the standard again in a few minutes" }
    }

    $Links = @($TrafficProfile.policies | Where-Object { $_ })
    $Assigned = $TrafficProfile.assignmentRules.assignments
    $AssignmentType = "$($Assigned.'@odata.type')"
    $IsEnumerated = $AssignmentType -like '*forwardingProfileAssignmentsEnumeratedMembership'
    $Current = [ordered]@{
        profileState       = "$($TrafficProfile.state)"
        policyLinksEnabled = $Links.Count -eq 0 -or @($Links | Where-Object { $_.state -ne 'enabled' }).Count -eq 0
        assignedToAllUsers = $AssignmentType -like '*forwardingProfileAssignmentsAllMembership'
    }
    $Expected = [ordered]@{
        profileState = $ProfileState
    }
    if ($ProfileState -eq 'enabled') {
        $Expected.policyLinksEnabled = $true
        if ($AssignTo -eq 'AllDevicesAndUsers') {
            $Expected.assignedToAllUsers = $true
        } elseif ($AssignTo -eq 'DoNotAssign') {
            $Expected.assignedToAllUsers = $false
            $Expected.nobodyAssigned = $true
            $Current.nobodyAssigned = $IsEnumerated -and
                @($Assigned.users | Where-Object { $_ }).Count -eq 0 -and
                @($Assigned.groups | Where-Object { $_ }).Count -eq 0 -and
                @($Assigned.devices | Where-Object { $_ }).Count -eq 0
        } else {
            $Expected.assignedToAllUsers = $false
            $Expected.configuredGroupsAssigned = $true
            # Additive: only the configured groups (wildcards allowed) are graded;
            # assignments an administrator made by hand are never drift.
            $AssignedIds = @($Assigned.groups | Where-Object { $_ } | ForEach-Object { "$($_.id)" })
            $Groups = @(Get-CIPPBaselineCacheRows -TenantFilter $TenantFilter -Type 'Groups')
            $MatchedIds = [System.Collections.Generic.List[string]]::new()
            $EveryPatternMatched = $true
            foreach ($Ref in $GroupRefs) {
                $Escaped = $Ref -replace '\[', '`[' -replace '\]', '`]'
                $Matched = @($Groups | Where-Object { $_.displayName -like $Escaped })
                if ($Matched.Count -eq 0) { $EveryPatternMatched = $false; continue }
                foreach ($Group in $Matched) { $MatchedIds.Add($Group.id) }
            }
            $Current.configuredGroupsAssigned = $EveryPatternMatched -and @($MatchedIds | Where-Object { $AssignedIds -notcontains $_ }).Count -eq 0
        }
    }
    @{ Expected = [PSCustomObject]$Expected; Current = [PSCustomObject]$Current }
}
