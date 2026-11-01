# GlobalSecureAccessM365Profile: the Microsoft 365 traffic forwarding profile standard.
# The assignment model is the profile's own assignmentRules - AllMembership (all users) or
# EnumeratedMembership (users/groups/devices) - which is what the Global Secure Access
# portal's User and device assignments blade reads and writes. The legacy enterprise-app
# surface (the profile app's appRoleAssignmentRequired flag and its appRoleAssignments) is
# dead: the portal does not read it, and writes to it change nothing the blade shows.
# CustomGroups grades the configured groups additively - hand-assigned groups, users and
# devices are preserved and never drift.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }

    . (Join-Path $Baselines 'Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $Baselines 'Helpers/Get-CIPPBaselineCacheRows.ps1')
    . (Join-Path $Baselines 'PrepareHooks/Get-CIPPBaselineGlobalSecureAccessM365ProfileState.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineGlobalSecureAccessM365Profile.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 25 | ConvertFrom-Json } }
    function Get-Verdict {
        param($Expected, $Current)
        $Projected = [PSCustomObject]@{}
        foreach ($Key in $Expected.PSObject.Properties.Name) { $Projected | Add-Member -NotePropertyName $Key -NotePropertyValue $Current.$Key }
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })
    }

    # One configured tenant: profile enabled, both policy links enabled, assigned to all users.
    $script:M365 = @{
        id = 'prof-m365'; name = 'Microsoft 365'; state = 'enabled'; trafficForwardingType = 'm365'; isCustomProfile = $false
        servicePrincipalId = 'sp-m365'
        assignmentRules = @{ assignments = @{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' } }
        policies = @(@{ id = 'link-exo'; state = 'enabled'; policyName = 'Exchange Online' }, @{ id = 'link-spo'; state = 'enabled'; policyName = 'SharePoint Online' })
    }
    function New-Row {
        param($Profile = $script:M365, $Onboarded = $true)
        @{
            id               = 'networkAccess'
            onboardingStatus = $(if ($Onboarded) { 'onboarded' } else { 'notOnboarded' })
            onboarded        = $Onboarded
            signalingStatus  = 'enabled'
            profiles         = $(if ($Profile) { @($Profile) } else { @() })
        }
    }
    function New-Enumerated {
        param($Groups = @(), $Users = @(), $Devices = @())
        @{ assignments = @{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsEnumeratedMembership'; users = @($Users); groups = @($Groups); devices = @($Devices) } }
    }
    function New-ItemVars {
        param([string]$ProfileState, [string]$AssignTo, $Groups)
        [PSCustomObject]@{
            profileState   = $ProfileState
            assignTo       = $AssignTo
            assignedGroups = $Groups
        }
    }
}

Describe 'Get-CIPPBaselineGlobalSecureAccessM365ProfileState' {
    BeforeAll {
        $script:GroupsCache = @(
            @{ id = 'g-pilot'; displayName = 'GSA Pilot' }
            @{ id = 'g-it'; displayName = 'IT' }
            @{ id = 'g-hand'; displayName = 'Hand Added By Admin' }
        )
    }
    BeforeEach {
        $script:Row = New-Row
        Mock Get-CIPPDbItem { [PSCustomObject]@{ RowKey = 'X-Count'; DataCount = 1 } }
        Mock New-CIPPDbRequest {
            if ($Type -eq 'Groups') { @($script:GroupsCache | ConvertTo-Cached) }
            elseif ($script:Row) { @($script:Row | ConvertTo-Cached) }
            else { @() }
        }
    }

    It 'grades a tenant in all-users mode compliant in default mode (enabled, all users)' {
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars) }) -TenantFilter $script:Tenant
        (Get-Verdict -Expected $P.Expected -Current $P.Current).Count | Should -Be 0
        $P.Expected.PSObject.Properties.Name | Should -Be @('profileState', 'policyLinksEnabled', 'assignedToAllUsers')
    }

    It 'applies the declared defaults when the variables are blank' {
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -ProfileState '' -AssignTo '') }) -TenantFilter $script:Tenant
        $P.Expected.profileState | Should -Be 'enabled'
        $P.Expected.assignedToAllUsers | Should -BeTrue
    }

    It 'grades drift on a disabled profile, a disabled policy link, and an enumerated (scoped) assignment' {
        $Profile = $script:M365.Clone()
        $Profile.state = 'disabled'
        $Profile.policies = @(@{ id = 'link-exo'; state = 'disabled'; policyName = 'Exchange Online' })
        $Profile.assignmentRules = New-Enumerated -Groups @(@{ id = 'g-hand' })
        $script:Row = New-Row -Profile $Profile
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars) }) -TenantFilter $script:Tenant
        $Differences = Get-Verdict -Expected $P.Expected -Current $P.Current
        @($Differences.Property | Sort-Object) | Should -Be @('assignedToAllUsers', 'policyLinksEnabled', 'profileState')
    }

    It 'grades only the profile state when the desired state is disabled - links and assignment express no opinion' {
        $Profile = $script:M365.Clone()
        $Profile.state = 'enabled'
        $script:Row = New-Row -Profile $Profile
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -ProfileState 'disabled') }) -TenantFilter $script:Tenant
        $P.Expected.PSObject.Properties.Name | Should -Be @('profileState')
        (Get-Verdict -Expected $P.Expected -Current $P.Current).Count | Should -Be 1
    }

    It 'grades CustomGroups additively: every configured group assigned is compliant, hand-assigned extras are never drift' {
        $Profile = $script:M365.Clone()
        $Profile.assignmentRules = New-Enumerated -Groups @(@{ id = 'g-pilot' }, @{ id = 'g-hand' })
        $script:Row = New-Row -Profile $Profile
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -AssignTo 'CustomGroups' -Groups @('GSA Pilot')) }) -TenantFilter $script:Tenant
        $P.Expected.PSObject.Properties.Name | Should -Be @('profileState', 'policyLinksEnabled', 'assignedToAllUsers', 'configuredGroupsAssigned')
        (Get-Verdict -Expected $P.Expected -Current $P.Current).Count | Should -Be 0
    }

    It 'grades drift when a configured group has no assignment, and when the profile is still all-users' {
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -AssignTo 'CustomGroups' -Groups @('GSA Pilot', 'IT')) }) -TenantFilter $script:Tenant
        $Differences = Get-Verdict -Expected $P.Expected -Current $P.Current
        @($Differences.Property | Sort-Object) | Should -Be @('assignedToAllUsers', 'configuredGroupsAssigned')
    }

    It 'grades drift for a configured group that does not resolve in the tenant - remediation throws if it truly does not exist' {
        $Profile = $script:M365.Clone()
        $Profile.assignmentRules = New-Enumerated -Groups @(@{ id = 'g-pilot' })
        $script:Row = New-Row -Profile $Profile
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -AssignTo 'CustomGroups' -Groups @('GSA Pilot', 'Does Not Exist')) }) -TenantFilter $script:Tenant
        (Get-Verdict -Expected $P.Expected -Current $P.Current).Property | Should -Contain 'configuredGroupsAssigned'
    }

    It 'refuses CustomGroups with no groups configured - a scoped profile nobody holds gives no user the profile' {
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -AssignTo 'CustomGroups') }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.ConfigError | Should -BeTrue
        $P.NoDataReason | Should -BeLike '*no groups are configured*'
    }

    It 'refuses an invalid profile state or assign mode as a configuration error' {
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -ProfileState 'paused') }) -TenantFilter $script:Tenant
        $P.ConfigError | Should -BeTrue
        $P.NoDataReason | Should -BeLike '*profileState*'
    }

    It 'names the onboarding prerequisite for a tenant that is not onboarded' {
        $script:Row = New-Row -Onboarded $false
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars) }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.NoDataReason | Should -BeLike '*not onboarded to Global Secure Access*Onboard Global Secure Access*'
    }

    It 'reports No Data while the default profile has not been created - onboarding settles asynchronously' {
        $script:Row = New-Row -Profile $null
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars) }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.NoDataReason | Should -BeLike '*has not been created*'
    }

    It 'returns plain No Data when the cache was never collected' {
        $script:Row = $null
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars) }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.NoDataReason | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-CIPPBaselineGlobalSecureAccessM365Profile' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock New-GraphPostRequest { }
        $script:LiveProfileState = 'enabled'
        $script:LiveLinkStates = @{ 'link-exo' = 'enabled'; 'link-spo' = 'enabled' }
        $script:LiveAssignmentType = 'AllMembership'
        $script:LiveAssignedGroups = @()
        $script:LiveAssignedUsers = @()
        $script:LiveAssignedDevices = @()
        Mock New-GraphGetRequest {
            switch -Wildcard ($uri) {
                '*networkAccess/forwardingProfiles*' {
                    @([PSCustomObject]@{
                            id = 'prof-m365'; name = 'Microsoft 365'; state = $script:LiveProfileState; trafficForwardingType = 'm365'; isCustomProfile = $false
                            servicePrincipal = [PSCustomObject]@{ id = 'sp-m365' }
                            policies         = @(
                                [PSCustomObject]@{ id = 'link-exo'; state = $script:LiveLinkStates['link-exo'] }
                                [PSCustomObject]@{ id = 'link-spo'; state = $script:LiveLinkStates['link-spo'] }
                            )
                            assignmentRules  = [PSCustomObject]@{
                                assignments           = if ($script:LiveAssignmentType -eq 'AllMembership') {
                                    [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' }
                                } else {
                                    [PSCustomObject]@{
                                        '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsEnumeratedMembership'
                                        users         = @($script:LiveAssignedUsers | ForEach-Object { [PSCustomObject]@{ id = $_ } })
                                        groups        = @($script:LiveAssignedGroups | ForEach-Object { [PSCustomObject]@{ id = $_ } })
                                        devices       = @($script:LiveAssignedDevices | ForEach-Object { [PSCustomObject]@{ id = $_ } })
                                    }
                                }
                                devicePropertyFilters = [PSCustomObject]@{ platforms = 'windows,macOS,android,iOS' }
                            }
                        })
                }
                '*groups?*' {
                    @(
                        [PSCustomObject]@{ id = 'g-pilot'; displayName = 'GSA Pilot' }
                        [PSCustomObject]@{ id = 'g-it'; displayName = 'IT' }
                    )
                }
                default { throw "unexpected uri: $uri" }
            }
        }
    }

    It 'reports Changed=false without writing anything on a fully configured tenant' {
        $Result = Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $null
        $Result.Changed | Should -BeFalse
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
    }

    It 'moves a scoped profile to all users with one profile PATCH carrying the AllMembership type - and never touches the legacy service principal' {
        $script:LiveAssignmentType = 'EnumeratedMembership'
        $script:LiveAssignedGroups = @('g-hand')
        $Result = Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $null
        $Result | Should -BeNullOrEmpty
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*networkAccess/forwardingProfiles/prof-m365' -and $body -like '*forwardingProfileAssignmentsAllMembership*' }
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*servicePrincipals*' }
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*servicePrincipals*' }
    }

    It 'enables the profile, every disabled policy link and the all-users assignment in one run' {
        $script:LiveProfileState = 'disabled'
        $script:LiveLinkStates['link-spo'] = 'disabled'
        $script:LiveAssignmentType = 'EnumeratedMembership'
        $Result = Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $null
        $Result | Should -BeNullOrEmpty
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*networkAccess/forwardingProfiles/prof-m365' -and $body -like '*"state":"enabled"*' }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*forwardingProfiles/prof-m365/policies/link-spo*' -and $body -like '*"state":"enabled"*' }
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*forwardingProfiles/prof-m365/policies/link-exo*' }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*networkAccess/forwardingProfiles/prof-m365' -and $body -like '*forwardingProfileAssignmentsAllMembership*' }
    }

    It 'scopes a profile to the configured groups from all-users mode, preserving the device platform filters' {
        $Remediate = [PSCustomObject]@{ assignTo = 'CustomGroups'; assignedGroups = @('GSA Pilot') }
        $Result = Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate $Remediate -TenantFilter $script:Tenant -Current $null
        $Result | Should -BeNullOrEmpty
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*networkAccess/forwardingProfiles/prof-m365' -and $body -like '*forwardingProfileAssignmentsEnumeratedMembership*' -and $body -like '*g-pilot*' -and $body -like '*devicePropertyFilters*' -and $body -like '*windows,macOS,android,iOS*' }
    }

    It 'adds only the missing configured groups, preserving hand-added groups, users and devices - additive' {
        $script:LiveAssignmentType = 'EnumeratedMembership'
        $script:LiveAssignedGroups = @('g-hand')
        $script:LiveAssignedUsers = @('u-1')
        $script:LiveAssignedDevices = @('d-1')
        $Remediate = [PSCustomObject]@{ assignTo = 'CustomGroups'; assignedGroups = @('GSA Pilot', 'IT') }
        $Result = Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate $Remediate -TenantFilter $script:Tenant -Current $null
        $Result | Should -BeNullOrEmpty
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*networkAccess/forwardingProfiles/prof-m365' -and $body -like '*g-hand*' -and $body -like '*g-pilot*' -and $body -like '*g-it*' -and $body -like '*u-1*' -and $body -like '*d-1*' }
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $type -eq 'DELETE' }
    }

    It 'writes nothing when every configured group already holds an assignment' {
        $script:LiveAssignmentType = 'EnumeratedMembership'
        $script:LiveAssignedGroups = @('g-pilot', 'g-it')
        $Remediate = [PSCustomObject]@{ assignTo = 'CustomGroups'; assignedGroups = @('GSA Pilot', 'IT') }
        $Result = Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate $Remediate -TenantFilter $script:Tenant -Current $null
        $Result.Changed | Should -BeFalse
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
    }

    It 'throws naming an unresolvable group, and refuses CustomGroups with no groups' {
        $Remediate = [PSCustomObject]@{ assignTo = 'CustomGroups'; assignedGroups = @('Does Not Exist') }
        { Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate $Remediate -TenantFilter $script:Tenant -Current $null } | Should -Throw '*Does Not Exist*'

        { Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate ([PSCustomObject]@{ assignTo = 'CustomGroups' }) -TenantFilter $script:Tenant -Current $null } | Should -Throw '*no groups are configured*'
    }

    It 'disables the profile and nothing else when the desired state is disabled' {
        $script:LiveProfileState = 'enabled'
        $script:LiveAssignmentType = 'EnumeratedMembership'
        $Result = Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate ([PSCustomObject]@{ profileState = 'disabled' }) -TenantFilter $script:Tenant -Current $null
        $Result | Should -BeNullOrEmpty
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*networkAccess/forwardingProfiles/prof-m365' -and $body -like '*"state":"disabled"*' }
        # already disabled: a no-op that grades compliant
        $script:LiveProfileState = 'disabled'
        $Result = Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate ([PSCustomObject]@{ profileState = 'disabled' }) -TenantFilter $script:Tenant -Current $null
        $Result.Changed | Should -BeFalse
    }

    It 'throws when the Microsoft 365 profile has not been created yet' {
        Mock New-GraphGetRequest { @() }
        { Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $null } | Should -Throw '*run the standard again in a few minutes*'
    }
}
