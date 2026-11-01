function Invoke-CIPPBaselineGlobalSecureAccessM365Profile {
    <#
    .SYNOPSIS
        GlobalSecureAccessM365Profile executor: brings the Microsoft 365 traffic
        forwarding profile to the configured state.
    .DESCRIPTION
        Extracted from the packaged compliant-network standard's proven tenant block.
        Reads the LIVE profile (remediation always works from live state), then writes
        only what differs: the profile state, every disabled policy link, and - in
        enabled mode - the assignment. AllUsers lifts the profile app's assignment
        requirement; CustomGroups resolves the configured group names live, refuses an
        unresolvable one, and assigns only the groups that do not already hold an
        assignment. Assignments are ADDITIVE: anything an administrator made by hand
        is never removed, in either mode. Disabled mode writes the profile state and
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
    if ($AssignTo -eq 'CustomGroups' -and $GroupRefs.Count -eq 0) { throw 'CustomGroups is selected but no groups are configured - a profile that requires assignment with no assigned groups gives no user the profile.' }

    $Profiles = @(New-GraphGetRequest -uri "$Graph/networkAccess/forwardingProfiles?`$expand=policies(`$expand=policy)" -tenantid $TenantFilter -AsApp $true)
    $TrafficProfile = $Profiles | Where-Object { $_.trafficForwardingType -eq 'm365' -and $_.isCustomProfile -ne $true } | Select-Object -First 1
    if (-not $TrafficProfile) { throw 'The Microsoft 365 traffic forwarding profile was not found; run the standard again in a few minutes.' }

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

    $SpId = $TrafficProfile.servicePrincipal.id
    if ($SpId) {
        if ($AssignTo -eq 'AllUsers') {
            $Sp = New-GraphGetRequest -uri "$Graph/servicePrincipals/$SpId`?`$select=id,appRoleAssignmentRequired" -tenantid $TenantFilter -AsApp $true
            if ($Sp.appRoleAssignmentRequired -ne $false) {
                $null = New-GraphPostRequest -uri "$Graph/servicePrincipals/$SpId" -tenantid $TenantFilter -type PATCH -body '{"appRoleAssignmentRequired":false}' -AsApp $true
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Assigned the Microsoft 365 traffic forwarding profile to all users.' -Sev 'Info'
                $Changed = $true
            }
        } else {
            # Resolve the configured group names live: the cache can lag a group created
            # moments ago, and an unresolved name must stop the run, not silently skip.
            $Groups = @(New-GraphGetRequest -uri "$Graph/groups?`$select=id,displayName&`$top=999" -tenantid $TenantFilter -AsApp $true)
            $Resolved = @{}
            foreach ($Ref in $GroupRefs) {
                $Match = $Groups | Where-Object { $_.displayName -eq $Ref } | Select-Object -First 1
                if (-not $Match) { throw "Group '$Ref' was not found and could not be assigned the traffic profile." }
                $Resolved[$Ref] = $Match.id
            }
            $Sp = New-GraphGetRequest -uri "$Graph/servicePrincipals/$SpId`?`$select=id,appRoleAssignmentRequired,appRoles&`$expand=appRoleAssignments(`$select=principalId)" -tenantid $TenantFilter -AsApp $true
            $AppRole = @($Sp.appRoles | Where-Object { $_ }) | Select-Object -First 1
            if (-not $AppRole) { throw 'The Microsoft 365 traffic forwarding profile exposes no app role to assign groups to.' }
            if ($Sp.appRoleAssignmentRequired -ne $true) {
                $null = New-GraphPostRequest -uri "$Graph/servicePrincipals/$SpId" -tenantid $TenantFilter -type PATCH -body '{"appRoleAssignmentRequired":true}' -AsApp $true
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Restricted the Microsoft 365 traffic forwarding profile to assigned groups.' -Sev 'Info'
                $Changed = $true
            }
            $AssignedIds = @($Sp.appRoleAssignments | Where-Object { $_ } | ForEach-Object { "$($_.principalId)" })
            # Additive: only the missing configured groups are assigned; assignments an
            # administrator made by hand are never removed.
            foreach ($Ref in $GroupRefs) {
                $PrincipalId = $Resolved[$Ref]
                if ($AssignedIds -contains $PrincipalId) { continue }
                $Body = @{ principalId = $PrincipalId; resourceId = $SpId; appRoleId = $AppRole.id } | ConvertTo-Json -Compress
                $null = New-GraphPostRequest -uri "$Graph/servicePrincipals/$SpId/appRoleAssignments" -tenantid $TenantFilter -type POST -body $Body -AsApp $true
                Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Assigned the Microsoft 365 traffic forwarding profile to group '$Ref'." -Sev 'Info'
                $Changed = $true
            }
        }
    }

    if (-not $Changed) { return [PSCustomObject]@{ Changed = $false } }
}
