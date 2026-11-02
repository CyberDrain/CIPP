function Invoke-CIPPBaselineForwardingProfile {
    <#
    .SYNOPSIS
        Shared remediation core for the Global Secure Access traffic forwarding profile
        standards (Microsoft 365, Internet).
    .DESCRIPTION
        The assignment follows the Intune template convention: AllDevicesAndUsers sets
        the AllMembership type, customGroup resolves the configured group names (comma
        separated, wildcards allowed) live and merges them into the live
        EnumeratedMembership, and DoNotAssign writes an empty EnumeratedMembership -
        refusing when that would mean removing assignments made by hand, which the
        operator does in the portal. Writes go through the forwarding profile PATCH the
        portal itself uses, in the portal's exact body shape and property order:
        devicePropertyFilters first with the comma-joined platforms string, then the
        assignments with @odata.type, users, devices, groups as {id} entries - the
        undocumented service deserializer is order sensitive. Everything hand-assigned
        is preserved; nothing is ever deleted; the legacy enterprise-app surface is not
        touched. Disabled mode writes the profile state and nothing else.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Remediate, $TenantFilter, $Current, [string]$TrafficType, [string]$ProfileLabel)

    $Graph = 'https://graph.microsoft.com/beta'
    $ProfileState = "$($Remediate.profileState)"
    if (-not $ProfileState) { $ProfileState = 'enabled' }
    $AssignTo = "$($Remediate.assignTo)"
    if (-not $AssignTo) { $AssignTo = 'AllDevicesAndUsers' }
    $GroupRefs = @("$($Remediate.customGroup)" -split ',' | ForEach-Object { "$_".Trim() } | Where-Object { $_ })

    if ($ProfileState -notin @('enabled', 'disabled')) { throw "profileState must be 'enabled' or 'disabled', not '$ProfileState'." }
    if ($AssignTo -notin @('DoNotAssign', 'AllDevicesAndUsers', 'customGroup')) { throw "assignTo must be 'DoNotAssign', 'AllDevicesAndUsers' or 'customGroup', not '$AssignTo'." }
    if ($AssignTo -eq 'customGroup' -and $GroupRefs.Count -eq 0) { throw 'customGroup is selected but no group name is configured - a scoped profile with no assigned groups gives no user the profile.' }

    $Profiles = @(New-GraphGetRequest -uri "$Graph/networkAccess/forwardingProfiles?`$expand=policies(`$expand=policy)" -tenantid $TenantFilter -AsApp $true)
    $TrafficProfile = $Profiles | Where-Object { $_.trafficForwardingType -eq $TrafficType -and $_.isCustomProfile -ne $true } | Select-Object -First 1
    if (-not $TrafficProfile) { throw "The $ProfileLabel traffic forwarding profile was not found; run the standard again in a few minutes." }

    # The write body must mirror the portal's own PATCH byte for byte, including property
    # order (devicePropertyFilters first) and the comma-joined platforms string the GET
    # returns - the array form is rejected and the omission is rejected. Captured live
    # from the portal's request on a test tenant.
    $Platforms = "$($TrafficProfile.assignmentRules.devicePropertyFilters.platforms)"
    if (-not $Platforms) { $Platforms = 'windows,macOS,android,iOS' }
    $PatchProfile = {
        param($Rules)
        $Body = @{ assignmentRules = $Rules } | ConvertTo-Json -Depth 10 -Compress
        $null = New-GraphPostRequest -uri "$Graph/networkAccess/forwardingProfiles/$($TrafficProfile.id)" -tenantid $TenantFilter -type PATCH -body $Body -AsApp $true
    }

    $Changed = $false
    if ($ProfileState -eq 'disabled') {
        if ($TrafficProfile.state -ne 'disabled') {
            $null = New-GraphPostRequest -uri "$Graph/networkAccess/forwardingProfiles/$($TrafficProfile.id)" -tenantid $TenantFilter -type PATCH -body '{"state":"disabled"}' -AsApp $true
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Disabled the $ProfileLabel traffic forwarding profile." -Sev 'Info'
            $Changed = $true
        }
        if (-not $Changed) { return [PSCustomObject]@{ Changed = $false } }
        return
    }

    if ($TrafficProfile.state -ne 'enabled') {
        $null = New-GraphPostRequest -uri "$Graph/networkAccess/forwardingProfiles/$($TrafficProfile.id)" -tenantid $TenantFilter -type PATCH -body '{"state":"enabled"}' -AsApp $true
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Enabled the $ProfileLabel traffic forwarding profile." -Sev 'Info'
        $Changed = $true
    }
    foreach ($Link in @($TrafficProfile.policies | Where-Object { $_.state -ne 'enabled' })) {
        $null = New-GraphPostRequest -uri "$Graph/networkAccess/forwardingProfiles/$($TrafficProfile.id)/policies/$($Link.id)" -tenantid $TenantFilter -type PATCH -body '{"state":"enabled"}' -AsApp $true
        $Changed = $true
    }

    $AssignmentType = "$($TrafficProfile.assignmentRules.assignments.'@odata.type')"
    $IsEnumerated = $AssignmentType -like '*forwardingProfileAssignmentsEnumeratedMembership'
    if ($AssignTo -eq 'AllDevicesAndUsers') {
        if ($AssignmentType -notlike '*forwardingProfileAssignmentsAllMembership') {
            $Rules = [ordered]@{
                devicePropertyFilters = [ordered]@{ platforms = $Platforms }
                assignments           = [ordered]@{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' }
            }
            & $PatchProfile $Rules
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Assigned the $ProfileLabel traffic forwarding profile to all users and devices." -Sev 'Info'
            $Changed = $true
        }
    } elseif ($AssignTo -eq 'DoNotAssign') {
        if (-not $IsEnumerated) {
            $Rules = [ordered]@{
                devicePropertyFilters = [ordered]@{ platforms = $Platforms }
                assignments           = [ordered]@{
                    '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsEnumeratedMembership'
                    users         = @()
                    devices       = @()
                    groups        = @()
                }
            }
            & $PatchProfile $Rules
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Unassigned the $ProfileLabel traffic forwarding profile." -Sev 'Info'
            $Changed = $true
        } else {
            $HasEntries = @($TrafficProfile.assignmentRules.assignments.users | Where-Object { $_ }).Count -gt 0 -or
                @($TrafficProfile.assignmentRules.assignments.groups | Where-Object { $_ }).Count -gt 0 -or
                @($TrafficProfile.assignmentRules.assignments.devices | Where-Object { $_ }).Count -gt 0
            if ($HasEntries) {
                throw 'Cannot set Do not assign without removing assignments made by hand - remove them in the portal, then run the standard again.'
            }
        }
    } else {
        # Resolve the configured group names live, wildcards allowed: the cache can lag
        # a group created moments ago, and an unresolved name must stop the run.
        $Groups = @(New-GraphGetRequest -uri "$Graph/groups?`$select=id,displayName&`$top=999" -tenantid $TenantFilter -AsApp $true)
        $ResolvedIds = [System.Collections.Generic.List[string]]::new()
        foreach ($Ref in $GroupRefs) {
            $Escaped = $Ref -replace '\[', '`[' -replace '\]', '`]'
            $Matched = @($Groups | Where-Object { $_.displayName -like $Escaped })
            if ($Matched.Count -eq 0) { throw "No group matches '$Ref' - it could not be assigned the traffic profile." }
            foreach ($Group in $Matched) { $ResolvedIds.Add($Group.id) }
        }

        # Merge into the live enumerated membership - additive: hand-assigned groups,
        # users and devices are preserved, as are the device platform filters.
        $ExistingUsers = @(); $ExistingGroups = @(); $ExistingDevices = @()
        if ($IsEnumerated) {
            $ExistingUsers = @($TrafficProfile.assignmentRules.assignments.users | Where-Object { $_ } | ForEach-Object { "$($_.id)" })
            $ExistingGroups = @($TrafficProfile.assignmentRules.assignments.groups | Where-Object { $_ } | ForEach-Object { "$($_.id)" })
            $ExistingDevices = @($TrafficProfile.assignmentRules.assignments.devices | Where-Object { $_ } | ForEach-Object { "$($_.id)" })
        }
        $Missing = @($ResolvedIds | Where-Object { $ExistingGroups -notcontains $_ })
        if (-not $IsEnumerated -or $Missing.Count -gt 0) {
            $AllGroups = @($ExistingGroups + $ResolvedIds | Sort-Object -Unique)
            # Portal-exact shape and order: devicePropertyFilters first, then the
            # enumerated assignments with users, devices and groups.
            $Rules = [ordered]@{
                devicePropertyFilters = [ordered]@{ platforms = $Platforms }
                assignments           = [ordered]@{
                    '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsEnumeratedMembership'
                    users         = @($ExistingUsers | ForEach-Object { @{ id = $_ } })
                    devices       = @($ExistingDevices | ForEach-Object { @{ id = $_ } })
                    groups        = @($AllGroups | ForEach-Object { @{ id = $_ } })
                }
            }
            & $PatchProfile $Rules
            Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Assigned the $ProfileLabel traffic forwarding profile to $($ResolvedIds.Count) group(s); assignments made by hand are preserved." -Sev 'Info'
            $Changed = $true
        }
    }

    if (-not $Changed) { return [PSCustomObject]@{ Changed = $false } }
}
