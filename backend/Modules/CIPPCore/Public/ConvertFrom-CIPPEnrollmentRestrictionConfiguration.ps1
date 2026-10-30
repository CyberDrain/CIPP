function ConvertFrom-CIPPEnrollmentRestrictionConfiguration {
    <#
    .SYNOPSIS
        Groups a tenant's single-platform restriction objects into CIPP enrollment restrictions.
    .DESCRIPTION
        Reads deviceEnrollmentConfigurations (the default restriction and other configuration
        types are skipped) and groups the singlePlatformRestriction objects by display name and
        CIPP platform, so the two objects behind an Android restriction come back as one. Each
        result carries the flat settings from ConvertTo-CIPPEnrollmentRestrictionSettings plus:

        - ids: every Graph object behind the restriction
        - priority: the lowest (highest precedence) priority among them
        - AssignTo / customGroup / groupIds / assignments: read from the objects' assignments when
          present; customGroup names come from -GroupNameById, falling back to the id, and the raw
          assignments are kept for Compare-CIPPIntuneAssignments
        - missingPlatformTypes: Graph types the platform needs but the tenant does not have,
          such as an Android restriction created with only one half

        Assignments are read from the first object that has them; the portal assigns both
        Android halves together.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Configurations,
        [hashtable]$GroupNameById = @{}
    )

    $PlatformByType = @{}
    $Map = Get-CIPPEnrollmentRestrictionPlatformTypes
    foreach ($Platform in $Map.Keys) { foreach ($Type in $Map[$Platform]) { $PlatformByType[$Type.PlatformType] = $Platform } }

    $Restrictions = @($Configurations | Where-Object {
            "$($_.'@odata.type')" -match 'deviceEnrollmentPlatformRestrictionConfiguration$' -and $PlatformByType.ContainsKey("$($_.platformType)")
        })

    foreach ($Group in ($Restrictions | Group-Object -Property { "$($PlatformByType["$($_.platformType)"])|$($_.displayName)" })) {
        $Objects = @($Group.Group)
        $Platform = $PlatformByType["$($Objects[0].platformType)"]
        $Flat = [ordered]@{
            displayName = "$($Objects[0].displayName)"
            description = "$($Objects[0].description)"
            platform    = $Platform
        }
        foreach ($Type in $Map[$Platform]) {
            $Object = $Objects | Where-Object { "$($_.platformType)" -eq $Type.PlatformType } | Select-Object -First 1
            $Prefix = $Type.Prefix
            $Name = { param($Field) if ($Prefix) { "$Prefix$($Field.Substring(0, 1).ToUpper())$($Field.Substring(1))" } else { $Field } }
            $Restriction = $Object.platformRestriction
            $Flat[(& $Name 'platformBlocked')] = [bool]$Restriction.platformBlocked
            $Flat[(& $Name 'personalDeviceEnrollmentBlocked')] = [bool]$Restriction.personalDeviceEnrollmentBlocked
            $Flat[(& $Name 'osMinimumVersion')] = "$($Restriction.osMinimumVersion)"
            $Flat[(& $Name 'osMaximumVersion')] = "$($Restriction.osMaximumVersion)"
            if ($Type.HasManufacturers) { $Flat['deviceAdminBlockedManufacturers'] = @($Restriction.blockedManufacturers) }
        }

        $Assigned = $Objects | Where-Object { $_.PSObject.Properties.Name -contains 'assignments' } | Select-Object -First 1
        $Assignments = @($Assigned.assignments | Where-Object { $_ })
        $GroupIds = @($Assignments.target | Where-Object { "$($_.'@odata.type')" -eq '#microsoft.graph.groupAssignmentTarget' } | ForEach-Object { "$($_.groupId)" } | Where-Object { $_ } | Sort-Object -Unique)
        $Flat['AssignTo'] = $(if (@($Assignments.target | Where-Object { "$($_.'@odata.type')" -eq '#microsoft.graph.allLicensedUsersAssignmentTarget' }).Count -gt 0) { 'allLicensedUsers' } elseif ($GroupIds.Count -gt 0) { 'customGroup' } else { 'On' })
        $Flat['customGroup'] = @($GroupIds | ForEach-Object { $GroupNameById[$_] ?? $_ })

        $Settings = ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject ([PSCustomObject]$Flat)
        $Priorities = @($Objects | ForEach-Object { $_.priority } | Where-Object { $null -ne $_ } | ForEach-Object { [int]$_ } | Sort-Object)
        $Settings.priority = $(if ($Priorities.Count -gt 0) { $Priorities[0] } else { $null })
        $Settings | Add-Member -NotePropertyMembers ([ordered]@{
                ids                  = @($Objects | ForEach-Object { "$($_.id)" })
                groupIds             = $GroupIds
                assignments          = $Assignments
                missingPlatformTypes = @($Map[$Platform] | Where-Object { $_.PlatformType -notin @($Objects.platformType) } | ForEach-Object { $_.PlatformType })
                lastModifiedDateTime = @($Objects | ForEach-Object { $_.lastModifiedDateTime } | Sort-Object -Descending)[0]
                assignmentsKnown     = $null -ne $Assigned
            })
        $Settings
    }
}
