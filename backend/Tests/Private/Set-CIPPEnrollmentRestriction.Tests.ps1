# Pester tests for the enrollment (device type) restriction helpers.
#
# The fixtures are the restrictions Neptune North holds: an Android restriction stored as two
# singlePlatformRestriction objects (androidForWork allowed from 13.0, android device
# administrator blocked) with the same name and group, plus a Windows restriction for all
# licensed users. Covered: settings normalization (AssignTo through Get-CIPPIntuneAssignTarget),
# the per-platform-type Graph bodies, grouping a tenant's objects back into restrictions
# (round-trip equal to the template that wrote them), and Set-CIPPEnrollmentRestriction's
# create/patch and priority behaviour, with assignment handed to Set-CIPPAssignedPolicy.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    foreach ($Name in @('Get-CIPPEnrollmentRestrictionPlatformTypes', 'ConvertTo-CIPPEnrollmentRestrictionSettings', 'New-CIPPEnrollmentRestrictionBody',
            'ConvertFrom-CIPPEnrollmentRestrictionConfiguration', 'Get-CIPPEnrollmentRestrictionProjection', 'Set-CIPPEnrollmentRestriction', 'Get-CIPPIntuneAssignTarget')) {
        $Path = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter "$Name.ps1" -File | Select-Object -First 1 -ExpandProperty FullName
        if (-not $Path) { throw "Could not locate $Name.ps1 under Modules/" }
        . $Path
    }

    function Get-CippException { [CmdletBinding()] param($Exception) [PSCustomObject]@{ NormalizedError = "$($Exception.Exception.Message ?? $Exception)" } }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp) }
    function New-GraphPOSTRequest { [CmdletBinding()] param($uri, $tenantid, $body, $type, $AsApp) }
    function Write-LogMessage { [CmdletBinding()] param($Headers, $API, $tenant, $message, $Sev, $LogData) }
    function Set-CIPPAssignedPolicy { [CmdletBinding()] param($GroupName, $GroupIds, $PolicyId, $Type, $TenantFilter, $AssignmentMode, $Headers, $APIName) }

    $script:Tenant = 'neptunenorth.co.uk'
    $script:ByodGroup = '3baf8b01-f9c5-4914-81b8-6afddfcb43e7'
    function New-Restriction {
        param($Id, $Name, $PlatformType, $Restriction, $Priority = 1, $Targets)
        [PSCustomObject]@{
            '@odata.type'                     = '#microsoft.graph.deviceEnrollmentPlatformRestrictionConfiguration'
            id                                = "$Id`_SinglePlatformRestriction"
            displayName                       = $Name
            description                       = 'Allows personally owned Android Enterprise work profile enrolment on Android 13.0 and later. Blocks Android device administrator.'
            priority                          = $Priority
            deviceEnrollmentConfigurationType = 'singlePlatformRestriction'
            platformType                      = $PlatformType
            platformRestriction               = [PSCustomObject]$Restriction
            assignments                       = @($Targets | ForEach-Object { [PSCustomObject]@{ target = [PSCustomObject]$_ } })
        }
    }
    function Get-NeptuneConfigurations {
        $Group = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $script:ByodGroup }
        @(
            [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.deviceEnrollmentPlatformRestrictionsConfiguration'; id = 'acc_DefaultPlatformRestrictions'; displayName = 'All users and all devices'; priority = 0 }
            New-Restriction -Id 'c39a' -Name 'Android - Baseline - BYOD - Enrolment Restriction' -PlatformType 'android' -Targets $Group -Restriction @{ platformBlocked = $true; personalDeviceEnrollmentBlocked = $false; osMinimumVersion = $null; osMaximumVersion = $null; blockedManufacturers = @() }
            New-Restriction -Id 'f471' -Name 'Android - Baseline - BYOD - Enrolment Restriction' -PlatformType 'androidForWork' -Targets $Group -Restriction @{ platformBlocked = $false; personalDeviceEnrollmentBlocked = $false; osMinimumVersion = '13.0'; osMaximumVersion = $null; blockedManufacturers = @() }
            New-Restriction -Id 'feba' -Name 'Windows - Corporate Only' -PlatformType 'windows' -Targets @{ '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget' } -Restriction @{ platformBlocked = $false; personalDeviceEnrollmentBlocked = $true; osMinimumVersion = $null; osMaximumVersion = $null; blockedManufacturers = @() }
        )
    }
    $script:AndroidTemplate = [PSCustomObject]@{
        displayName                = 'Android - Baseline - BYOD - Enrolment Restriction'
        description                = 'Allows personally owned Android Enterprise work profile enrolment on Android 13.0 and later. Blocks Android device administrator.'
        platform                   = 'android'
        priority                   = 1
        osMinimumVersion           = '13.0'
        deviceAdminPlatformBlocked = $true
        AssignTo                   = 'customGroup'
        customGroup                = 'Android - Baseline - BYOD - App Protection - Include'
    }
}

Describe 'ConvertTo-CIPPEnrollmentRestrictionSettings' {
    It 'unwraps option objects, converts switch strings and joins group names' {
        $Settings = ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject @{
            displayName                     = ' iOS BYOD '
            platform                        = @{ value = 'ios'; label = 'iOS/iPadOS' }
            personalDeviceEnrollmentBlocked = 'true'
            priority                        = '2'
            AssignTo                        = @{ value = 'customgroup'; label = 'Assign to Custom Group' }
            customGroup                     = @('BYOD Users', 'Pilot*')
            deviceAdminBlockedManufacturers = @(@{ value = 'Samsung' }, 'Acme')
        }
        $Settings.displayName | Should -Be 'iOS BYOD'
        $Settings.platform | Should -Be 'ios'
        $Settings.personalDeviceEnrollmentBlocked | Should -BeTrue
        $Settings.priority | Should -Be 2
        # Canonical casing comes back from Get-CIPPIntuneAssignTarget.
        $Settings.AssignTo | Should -BeExactly 'customGroup'
        $Settings.customGroup | Should -Be 'BYOD Users, Pilot*'
        $Settings.deviceAdminBlockedManufacturers | Should -Be @('Acme', 'Samsung')
    }

    It 'treats anything but all users or custom groups as do not assign, and rejects a bad priority' {
        (ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject @{ platform = 'ios'; AssignTo = 'AllDevices' }).AssignTo | Should -Be 'On'
        (ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject @{ platform = 'ios' }).AssignTo | Should -Be 'On'
        { ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject @{ platform = 'ios'; priority = 0 } } | Should -Throw '*Priority*'
    }
}

Describe 'New-CIPPEnrollmentRestrictionBody' {
    It 'writes Android as a work profile object and a device administrator object, as Intune does' {
        $Bodies = New-CIPPEnrollmentRestrictionBody -Settings (ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject $script:AndroidTemplate)

        @($Bodies.Keys) | Should -Be @('androidForWork', 'android')
        $Bodies.androidForWork.platformRestriction.platformBlocked | Should -BeFalse
        $Bodies.androidForWork.platformRestriction.osMinimumVersion | Should -Be '13.0'
        $Bodies.androidForWork.platformRestriction.osMaximumVersion | Should -BeNullOrEmpty
        $Bodies.android.platformRestriction.platformBlocked | Should -BeTrue
        $Bodies.android.displayName | Should -Be $Bodies.androidForWork.displayName
    }

    It 'leaves OS versions off macOS and manufacturers off every non device administrator type' {
        $Bodies = New-CIPPEnrollmentRestrictionBody -Settings (ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject @{ displayName = 'Mac'; platform = 'macOS'; osMinimumVersion = '14.0'; deviceAdminBlockedManufacturers = 'Acme' })
        @($Bodies.Keys) | Should -Be @('mac')
        $Bodies.mac.platformRestriction.osMinimumVersion | Should -BeNullOrEmpty
        @($Bodies.mac.platformRestriction.blockedManufacturers).Count | Should -Be 0
    }
}

Describe 'ConvertFrom-CIPPEnrollmentRestrictionConfiguration' {
    It 'groups the two Android objects into one restriction and skips the default' {
        $Restrictions = @(ConvertFrom-CIPPEnrollmentRestrictionConfiguration -Configurations (Get-NeptuneConfigurations) -GroupNameById @{ $script:ByodGroup = 'Android - Baseline - BYOD - App Protection - Include' })

        $Restrictions.Count | Should -Be 2
        $Android = $Restrictions | Where-Object platform -EQ 'android'
        $Android.ids | Should -Be @('c39a_SinglePlatformRestriction', 'f471_SinglePlatformRestriction')
        $Android.osMinimumVersion | Should -Be '13.0'
        $Android.deviceAdminPlatformBlocked | Should -BeTrue
        $Android.AssignTo | Should -Be 'customGroup'
        $Android.customGroup | Should -Be 'Android - Baseline - BYOD - App Protection - Include'
        @($Android.assignments).Count | Should -Be 1
        $Android.missingPlatformTypes.Count | Should -Be 0
        ($Restrictions | Where-Object platform -EQ 'windows').AssignTo | Should -Be 'allLicensedUsers'
    }

    It 'reads back exactly what the template that wrote it grades' {
        $Template = ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject $script:AndroidTemplate
        $Android = @(ConvertFrom-CIPPEnrollmentRestrictionConfiguration -Configurations (Get-NeptuneConfigurations)) | Where-Object platform -EQ 'android'
        (ConvertTo-Json (Get-CIPPEnrollmentRestrictionProjection -Settings $Android -Platform 'android') -Compress) |
            Should -Be (ConvertTo-Json (Get-CIPPEnrollmentRestrictionProjection -Settings $Template -Platform 'android') -Compress)
    }

    It 'reports an Android restriction missing its device administrator half' {
        $Configurations = @(Get-NeptuneConfigurations | Where-Object { $_.platformType -ne 'android' })
        $Android = @(ConvertFrom-CIPPEnrollmentRestrictionConfiguration -Configurations $Configurations) | Where-Object platform -EQ 'android'
        $Android.missingPlatformTypes | Should -Be @('android')
    }
}

Describe 'Set-CIPPEnrollmentRestriction' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Existing = @()
        Mock New-GraphGetRequest -MockWith { $script:Existing }
        Mock New-GraphPOSTRequest -MockWith {
            $script:Writes.Add([PSCustomObject]@{ uri = $uri; type = $type; body = $body })
            [PSCustomObject]@{ id = "new-$($script:Writes.Count)" }
        }
        Mock Set-CIPPAssignedPolicy { }
        Mock Write-LogMessage { }
        $script:Settings = ConvertTo-CIPPEnrollmentRestrictionSettings -InputObject $script:AndroidTemplate
    }

    It 'creates both Android objects, sets their priority and assigns each through Set-CIPPAssignedPolicy' {
        $Result = Set-CIPPEnrollmentRestriction -TenantFilter $script:Tenant -Settings $script:Settings

        $Result | Should -BeLike 'Created android enrollment restriction*'
        @($script:Writes | Where-Object { $_.type -eq 'POST' -and $_.uri -like '*/deviceEnrollmentConfigurations' }).Count | Should -Be 2
        $Priority = @($script:Writes | Where-Object { $_.uri -like '*/setPriority' })
        $Priority.Count | Should -Be 2
        ($Priority[0].body | ConvertFrom-Json).priority | Should -Be 1
        Should -Invoke Set-CIPPAssignedPolicy -Times 2 -Exactly -ParameterFilter {
            $Type -eq 'deviceEnrollmentConfigurations' -and $AssignmentMode -eq 'replace' -and
            $GroupName -eq 'Android - Baseline - BYOD - App Protection - Include' -and $PolicyId -like 'new-*'
        }
    }

    It 'patches existing objects without the platform type and leaves their priority alone' {
        $script:Existing = Get-NeptuneConfigurations
        $script:Settings.priority = 3

        $null = Set-CIPPEnrollmentRestriction -TenantFilter $script:Tenant -Settings $script:Settings

        $Patches = @($script:Writes | Where-Object { $_.type -eq 'PATCH' })
        $Patches.Count | Should -Be 2
        $Patches | ForEach-Object { ($_.body | ConvertFrom-Json).PSObject.Properties.Name | Should -Not -Contain 'platformType' }
        @($script:Writes | Where-Object { $_.uri -like '*/setPriority' }).Count | Should -Be 0
    }

    It 'moves an existing restriction to a new priority when editing' {
        $script:Existing = Get-NeptuneConfigurations
        $script:Settings.priority = 3

        $null = Set-CIPPEnrollmentRestriction -TenantFilter $script:Tenant -Settings $script:Settings -ConfigurationIds @('c39a_SinglePlatformRestriction', 'f471_SinglePlatformRestriction') -PriorityMode Always

        @($script:Writes | Where-Object { $_.uri -like '*/c39a_SinglePlatformRestriction/setPriority' -or $_.uri -like '*/f471_SinglePlatformRestriction/setPriority' }).Count | Should -Be 2
    }

    It 'passes picked group ids through, and assigns all users by the broad target name' {
        $null = Set-CIPPEnrollmentRestriction -TenantFilter $script:Tenant -Settings $script:Settings -GroupIds @('picked-1')
        Should -Invoke Set-CIPPAssignedPolicy -Times 2 -Exactly -ParameterFilter { $GroupIds -contains 'picked-1' }

        $script:Settings.AssignTo = 'allLicensedUsers'
        $null = Set-CIPPEnrollmentRestriction -TenantFilter $script:Tenant -Settings $script:Settings -GroupIds @('picked-1')
        Should -Invoke Set-CIPPAssignedPolicy -Times 2 -Exactly -ParameterFilter { $GroupName -eq 'allLicensedUsers' -and -not $GroupIds }
    }

    It 'leaves the assignment alone for do not assign' {
        $script:Settings.AssignTo = 'On'
        $null = Set-CIPPEnrollmentRestriction -TenantFilter $script:Tenant -Settings $script:Settings
        Should -Invoke Set-CIPPAssignedPolicy -Times 0
    }

    It 'reports an assignment failure as a failed write' {
        Mock Set-CIPPAssignedPolicy { throw 'No groups found matching the specified name(s)' }
        { Set-CIPPEnrollmentRestriction -TenantFilter $script:Tenant -Settings $script:Settings } | Should -Throw '*No groups found*'
    }
}
