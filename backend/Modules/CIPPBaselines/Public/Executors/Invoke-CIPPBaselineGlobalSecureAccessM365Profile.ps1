function Invoke-CIPPBaselineGlobalSecureAccessM365Profile {
    <#
    .SYNOPSIS
        GlobalSecureAccessM365Profile executor: brings the Microsoft 365 traffic
        forwarding profile to the configured state.
    .DESCRIPTION
        Extracted from the packaged compliant-network standard's proven tenant block,
        with the assignment rewritten to the model the Global Secure Access portal
        actually uses: the profile's own assignmentRules, written through a PATCH of the
        forwarding profile. AllUsers sets the AllMembership type; CustomGroups resolves
        the configured group names live (stopping on an unresolvable one) and merges them
        into the live EnumeratedMembership - ADDITIVELY: hand-assigned groups, users and
        devices are preserved, as are the profile's device platform filters, and nothing
        is ever deleted. The legacy enterprise-app surface (the profile app's
        appRoleAssignmentRequired flag and its appRoleAssignments) is deliberately not
        touched: the portal does not read it. Disabled mode writes the profile state and
        nothing else.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Remediate, $TenantFilter, $Current)

    $Graph = 'https://graph.microsoft.com/beta'
    $ProfileState = "$($Remediate.profileState)"
    if (-not $ProfileState) { $ProfileState = 'enabled' }
    $AssignTo = "$($Remediate.assignTo)"
    if (-not $AssignTo) { $AssignTo = 'AllUsers' }
    $GroupRefs = @($Remediate.assignedGroups | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ })

    if ($ProfileState -notin @('enabled', 'disabled')) { throw "profileState must be 'enabled' or 'disabled', not '$ProfileState'." }
    if ($AssignTo -eq 'CustomGroups' -and $GroupRefs.Count -eq 0) { throw 'CustomGroups is selected but no groups are configured - a scoped profile with no assigned groups gives no user the profile.' }

    $Profiles = @(New-GraphGetRequest -uri "$Graph/networkAccess/forwardingProfiles?`$expand=policies(`$expand=policy)" -tenantid $TenantFilter -AsApp $true)
    $TrafficProfile = $Profiles | Where-Object { $_.trafficForwardingType -eq 'm365' -and $_.isCustomProfile -ne $true } | Select-Object -First 1
    if (-not $TrafficProfile) { throw 'The Microsoft 365 traffic forwarding profile was not found; run the standard again in a few minutes.' }

    $PatchProfile = {
        param($Rules)
        $Body = @{ assignmentRules = $Rules } | ConvertTo-Json -Depth 10 -Compress
        $null = New-GraphPostRequest -uri "$Graph/networkAccess/forwardingProfiles/$($TrafficProfile.id)" -tenantid $TenantFilter -type PATCH -body $Body -AsApp $true
    }

    $Changed = $false
    if ($ProfileState -eq 'disabled') {
        if ($TrafficProfile.state -ne 'disabled') {
            $null = New-GraphPostRequest -uri "$Graph/networkAccess/forwardingProfiles/$($TrafficProfile.id)" -tenantid $TenantFilter -type PATCH -body '{"state":"disabled"}' -AsApp $true
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Disabled the Microsoft 365 traffic forwarding profile.' -Sev 'Info'
            $Changed = $true
        }
        if (-not $Changed) { return [PSCustomObject]@{ Changed = $false } }
        return
    }

    if ($TrafficProfile.state -ne 'enabled') {
        $null = New-GraphPostRequest -uri "$Graph/networkAccess/forwardingProfiles/$($TrafficProfile.id)" -tenantid $TenantFilter -type PATCH -body '{"state":"enabled"}' -AsApp $true
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Enabled the Microsoft 365 traffic forwarding profile.' -Sev 'Info'
        $Changed = $true
    }
    foreach ($Link in @($TrafficProfile.policies | Where-Object { $_.state -ne 'enabled' })) {
        $null = New-GraphPostRequest -uri "$Graph/networkAccess/forwardingProfiles/$($TrafficProfile.id)/policies/$($Link.id)" -tenantid $TenantFilter -type PATCH -body '{"state":"enabled"}' -AsApp $true
        $Changed = $true
    }

    $AssignmentType = "$($TrafficProfile.assignmentRules.assignments.'@odata.type')"
    if ($AssignTo -eq 'AllUsers') {
        if ($AssignmentType -notlike '*forwardingProfileAssignmentsAllMembership') {
            $Rules = @{ assignments = @{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' } }
            if ($TrafficProfile.assignmentRules.devicePropertyFilters) { $Rules.devicePropertyFilters = $TrafficProfile.assignmentRules.devicePropertyFilters }
            & $PatchProfile $Rules
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Assigned the Microsoft 365 traffic forwarding profile to all users.' -Sev 'Info'
            $Changed = $true
        }
    } else {
        # Resolve the configured group names live: the cache can lag a group created
        # moments ago, and an unresolved name must stop the run, not silently skip.
        $Groups = @(New-GraphGetRequest -uri "$Graph/groups?`$select=id,displayName&`$top=999" -tenantid $TenantFilter -AsApp $true)
        $ResolvedIds = [System.Collections.Generic.List[string]]::new()
        foreach ($Ref in $GroupRefs) {
            $Match = $Groups | Where-Object { $_.displayName -eq $Ref } | Select-Object -First 1
            if (-not $Match) { throw "Group '$Ref' was not found and could not be assigned the traffic profile." }
            $ResolvedIds.Add($Match.id)
        }

        # Merge into the live enumerated membership - additive: hand-assigned groups,
        # users and devices are preserved, as are the device platform filters.
        $ExistingUsers = @(); $ExistingGroups = @(); $ExistingDevices = @()
        if ($AssignmentType -like '*forwardingProfileAssignmentsEnumeratedMembership') {
            $ExistingUsers = @($TrafficProfile.assignmentRules.assignments.users | Where-Object { $_ } | ForEach-Object { "$($_.id)" })
            $ExistingGroups = @($TrafficProfile.assignmentRules.assignments.groups | Where-Object { $_ } | ForEach-Object { "$($_.id)" })
            $ExistingDevices = @($TrafficProfile.assignmentRules.assignments.devices | Where-Object { $_ } | ForEach-Object { "$($_.id)" })
        }
        $Missing = @($ResolvedIds | Where-Object { $ExistingGroups -notcontains $_ })
        if ($AssignmentType -notlike '*forwardingProfileAssignmentsEnumeratedMembership' -or $Missing.Count -gt 0) {
            $AllGroups = @($ExistingGroups + $ResolvedIds | Sort-Object -Unique)
            $Rules = @{
                assignments = @{
                    '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsEnumeratedMembership'
                    users         = @($ExistingUsers | ForEach-Object { @{ id = $_ } })
                    groups        = @($AllGroups | ForEach-Object { @{ id = $_ } })
                    devices       = @($ExistingDevices | ForEach-Object { @{ id = $_ } })
                }
            }
            if ($TrafficProfile.assignmentRules.devicePropertyFilters) { $Rules.devicePropertyFilters = $TrafficProfile.assignmentRules.devicePropertyFilters }
            & $PatchProfile $Rules
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Assigned the Microsoft 365 traffic forwarding profile to $($ResolvedIds.Count) group(s); assignments made by hand are preserved." -Sev 'Info'
            $Changed = $true
        }
    }

    if (-not $Changed) { return [PSCustomObject]@{ Changed = $false } }
}
