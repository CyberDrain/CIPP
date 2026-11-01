# GlobalSecureAccessM365Profile: the Microsoft 365 traffic forwarding profile standard.
# The hook grades from the NetworkAccess cache (built-in GSA pattern), with a conditional
# expected: disabled expresses an opinion on the profile state alone; CustomGroups grades
# the configured groups against the cached assignments, additively - hand-assigned groups
# are never drift and never removed. The executor extracts the comprehensive standard's
# proven tenant block and never deletes an assignment.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }

    . (Join-Path $Baselines 'Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $Baselines 'PrepareHooks/Get-CIPPBaselineGlobalSecureAccessM365ProfileState.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineGlobalSecureAccessM365Profile.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 25 | ConvertFrom-Json } }
    function Get-Verdict {
        param($Expected, $Current)
        $Projected = [PSCustomObject]@{}
        foreach ($Key in $Expected.PSObject.Properties.Name) { $Projected | Add-Member -NotePropertyName $Key -NotePropertyValue $Current.$Key }
        @(Compare-CIPPIntuneObject -ReferenceObject $Expected -DifferenceObject $Projected | Where-Object { $_ })
    }
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneCompareExclusions.ps1')
    . (Join-Path $script:RepoRoot 'Modules/CIPPCore/Public/Compare-CIPPIntuneObject.ps1')

    # One configured tenant: profile enabled, both policy links enabled, assigned to all users.
    $script:M365 = @{
        id = 'prof-m365'; name = 'Microsoft 365'; state = 'enabled'; trafficForwardingType = 'm365'; isCustomProfile = $false
        servicePrincipalId = 'sp-m365'; appRoleAssignmentRequired = $false
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
    function New-ItemVars {
        param([string]$ProfileState, [string]$AssignTo, $Groups)
        [PSCustomObject]@{
            profileState  = $ProfileState
            assignTo      = $AssignTo
            assignedGroups = $Groups
        }
    }
}

Describe 'Get-CIPPBaselineGlobalSecureAccessM365ProfileState' {
    It 'grades a fully configured tenant compliant in default mode (enabled, all users)' {
        Mock New-CIPPDbRequest { @(New-Row | ConvertTo-Cached) }
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars) }) -TenantFilter $script:Tenant
        (Get-Verdict -Expected $P.Expected -Current $P.Current).Count | Should -Be 0
        $P.Expected.PSObject.Properties.Name | Should -Be @('profileState', 'policyLinksEnabled', 'assignedToAllUsers')
    }

    It 'applies the declared defaults when the variables are blank' {
        Mock New-CIPPDbRequest { @(New-Row | ConvertTo-Cached) }
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -ProfileState '' -AssignTo '') }) -TenantFilter $script:Tenant
        $P.Expected.profileState | Should -Be 'enabled'
        $P.Expected.assignedToAllUsers | Should -BeTrue
    }

    It 'grades drift on a disabled profile, a disabled policy link, and an assignment-required profile' {
        Mock New-CIPPDbRequest {
            $Profile = $script:M365.Clone()
            $Profile.state = 'disabled'
            $Profile.policies = @(@{ id = 'link-exo'; state = 'disabled'; policyName = 'Exchange Online' })
            $Profile.appRoleAssignmentRequired = $true
            @(New-Row -Profile $Profile | ConvertTo-Cached)
        }
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars) }) -TenantFilter $script:Tenant
        $Differences = Get-Verdict -Expected $P.Expected -Current $P.Current
        @($Differences.Property | Sort-Object) | Should -Be @('assignedToAllUsers', 'policyLinksEnabled', 'profileState')
    }

    It 'grades only the profile state when the desired state is disabled - links and assignment express no opinion' {
        Mock New-CIPPDbRequest {
            $Profile = $script:M365.Clone()
            $Profile.state = 'enabled'
            @(New-Row -Profile $Profile | ConvertTo-Cached)
        }
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -ProfileState 'disabled') }) -TenantFilter $script:Tenant
        $P.Expected.PSObject.Properties.Name | Should -Be @('profileState')
        (Get-Verdict -Expected $P.Expected -Current $P.Current).Count | Should -Be 1
    }

    It 'grades CustomGroups additively: every configured group assigned is compliant, hand-assigned extras are never drift' {
        Mock New-CIPPDbRequest {
            $Profile = $script:M365.Clone()
            $Profile.appRoleAssignmentRequired = $true
            $Profile.assignments = @(
                @{ principalId = 'g-pilot'; principalDisplayName = 'GSA Pilot' }
                @{ principalId = 'g-hand'; principalDisplayName = 'Hand Added By Admin' }
            )
            @(New-Row -Profile $Profile | ConvertTo-Cached)
        }
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -AssignTo 'CustomGroups' -Groups @('GSA Pilot')) }) -TenantFilter $script:Tenant
        $P.Expected.PSObject.Properties.Name | Should -Be @('profileState', 'policyLinksEnabled', 'assignedToAllUsers', 'configuredGroupsAssigned')
        (Get-Verdict -Expected $P.Expected -Current $P.Current).Count | Should -Be 0
    }

    It 'grades drift when a configured group has no assignment, and when the profile is still all-users' {
        Mock New-CIPPDbRequest {
            $Profile = $script:M365.Clone()
            $Profile.appRoleAssignmentRequired = $false
            $Profile.assignments = @()
            @(New-Row -Profile $Profile | ConvertTo-Cached)
        }
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -AssignTo 'CustomGroups' -Groups @('GSA Pilot', 'IT')) }) -TenantFilter $script:Tenant
        $Differences = Get-Verdict -Expected $P.Expected -Current $P.Current
        @($Differences.Property | Sort-Object) | Should -Be @('assignedToAllUsers', 'configuredGroupsAssigned')
    }

    It 'refuses CustomGroups with no groups configured - an assignment-required profile nobody holds gives no user the profile' {
        Mock New-CIPPDbRequest { @(New-Row | ConvertTo-Cached) }
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -AssignTo 'CustomGroups') }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.ConfigError | Should -BeTrue
        $P.NoDataReason | Should -BeLike '*no groups are configured*'
    }

    It 'refuses an invalid profile state or assign mode as a configuration error' {
        Mock New-CIPPDbRequest { @(New-Row | ConvertTo-Cached) }
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -ProfileState 'paused') }) -TenantFilter $script:Tenant
        $P.ConfigError | Should -BeTrue
        $P.NoDataReason | Should -BeLike '*profileState*'
    }

    It 'names the onboarding prerequisite for a tenant that is not onboarded' {
        Mock New-CIPPDbRequest { @(New-Row -Onboarded $false | ConvertTo-Cached) }
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars) }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.NoDataReason | Should -BeLike '*not onboarded to Global Secure Access*Onboard Global Secure Access*'
    }

    It 'reports No Data while the default profile has not been created - onboarding settles asynchronously' {
        Mock New-CIPPDbRequest { @(New-Row -Profile $null | ConvertTo-Cached) }
        $P = Get-CIPPBaselineGlobalSecureAccessM365ProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars) }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.NoDataReason | Should -BeLike '*has not been created*'
    }

    It 'returns plain No Data when the cache was never collected' {
        Mock New-CIPPDbRequest { @() }
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
        $script:LiveSpFlag = $false
        $script:LiveAssignments = @([PSCustomObject]@{ principalId = 'g-pilot' })
        $script:LiveAppRoles = @([PSCustomObject]@{ id = 'role-1' })
        Mock New-GraphGetRequest {
            switch -Wildcard ($uri) {
                '*networkAccess/forwardingProfiles*' {
                    @([PSCustomObject]@{
                            id = 'prof-m365'; name = 'Microsoft 365'; state = $script:LiveProfileState; trafficForwardingType = 'm365'; isCustomProfile = $false
                            servicePrincipal = [PSCustomObject]@{ id = 'sp-m365' }
                            policies = @(
                                [PSCustomObject]@{ id = 'link-exo'; state = $script:LiveLinkStates['link-exo'] }
                                [PSCustomObject]@{ id = 'link-spo'; state = $script:LiveLinkStates['link-spo'] }
                            )
                        })
                }
                '*servicePrincipals/sp-m365*' {
                    [PSCustomObject]@{
                        id                        = 'sp-m365'
                        appRoleAssignmentRequired = $script:LiveSpFlag
                        appRoleAssignments        = $script:LiveAssignments
                        appRoles                  = $script:LiveAppRoles
                    }
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

    It 'enables the profile, every disabled policy link and the all-users assignment in one run' {
        $script:LiveProfileState = 'disabled'
        $script:LiveLinkStates['link-spo'] = 'disabled'
        $script:LiveSpFlag = $true
        $Result = Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $null
        $Result | Should -BeNullOrEmpty
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*networkAccess/forwardingProfiles/prof-m365' -and $body -like '*"state":"enabled"*' }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*forwardingProfiles/prof-m365/policies/link-spo*' -and $body -like '*"state":"enabled"*' }
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*forwardingProfiles/prof-m365/policies/link-exo*' }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*servicePrincipals/sp-m365*' -and $body -like '*"appRoleAssignmentRequired":false*' }
    }

    It 'assigns only the missing groups in CustomGroups mode, additively - existing assignments and hand-added groups are never touched' {
        $script:LiveSpFlag = $true
        $script:LiveAssignments = @([PSCustomObject]@{ principalId = 'g-pilot' })
        $Remediate = [PSCustomObject]@{ assignTo = 'CustomGroups'; assignedGroups = @('GSA Pilot', 'IT') }
        $Result = Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate $Remediate -TenantFilter $script:Tenant -Current $null
        $Result | Should -BeNullOrEmpty
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*appRoleAssignmentRequired*' }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/appRoleAssignments*' -and $body -like '*"principalId":"g-it"*' }
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*/appRoleAssignments*' -and $body -like '*g-pilot*' }
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $type -eq 'DELETE' }
    }

    It 'sets the assignment-required flag when entering CustomGroups mode from all-users' {
        $script:LiveSpFlag = $false
        $script:LiveAssignments = @()
        $Remediate = [PSCustomObject]@{ assignTo = 'CustomGroups'; assignedGroups = @('GSA Pilot') }
        Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate $Remediate -TenantFilter $script:Tenant -Current $null | Out-Null
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*servicePrincipals/sp-m365*' -and $body -like '*"appRoleAssignmentRequired":true*' }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/appRoleAssignments*' }
    }

    It 'throws naming an unresolvable group, and refuses CustomGroups with no groups' {
        $Remediate = [PSCustomObject]@{ assignTo = 'CustomGroups'; assignedGroups = @('Does Not Exist') }
        { Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate $Remediate -TenantFilter $script:Tenant -Current $null } | Should -Throw '*Does Not Exist*'

        { Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate ([PSCustomObject]@{ assignTo = 'CustomGroups' }) -TenantFilter $script:Tenant -Current $null } | Should -Throw '*no groups are configured*'
    }

    It 'throws when the profile exposes no app role to assign groups to' {
        $script:LiveAppRoles = @()
        $Remediate = [PSCustomObject]@{ assignTo = 'CustomGroups'; assignedGroups = @('GSA Pilot') }
        { Invoke-CIPPBaselineGlobalSecureAccessM365Profile -Remediate $Remediate -TenantFilter $script:Tenant -Current $null } | Should -Throw '*no app role*'
    }

    It 'disables the profile and nothing else when the desired state is disabled' {
        $script:LiveProfileState = 'enabled'
        $script:LiveSpFlag = $true
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
