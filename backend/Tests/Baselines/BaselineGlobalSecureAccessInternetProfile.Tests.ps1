# GlobalSecureAccessInternetProfile: the Internet traffic forwarding profile standard.
# The hook and executor are thin wrappers over the shared forwarding-profile core (see
# BaselineGlobalSecureAccessM365Profile.Tests.ps1 for the deep coverage of that core);
# these tests prove the wrapper targets the Internet profile - the fixtures always
# include a Microsoft 365 profile too, so a wrong profile selection fails loudly.

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
    . (Join-Path $Baselines 'Helpers/Get-CIPPBaselineForwardingProfileState.ps1')
    . (Join-Path $Baselines 'Helpers/Invoke-CIPPBaselineForwardingProfile.ps1')
    . (Join-Path $Baselines 'PrepareHooks/Get-CIPPBaselineGlobalSecureAccessInternetProfileState.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineGlobalSecureAccessInternetProfile.ps1')
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

    $script:Internet = @{
        id = 'prof-inet'; name = 'Internet'; state = 'enabled'; trafficForwardingType = 'internet'; isCustomProfile = $false
        assignmentRules = @{ assignments = @{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' } }
        policies = @(@{ id = 'link-acq'; state = 'enabled'; policyName = 'Default Acquire' }, @{ id = 'link-byp'; state = 'enabled'; policyName = 'Default bypass' })
    }
    $script:M365Sibling = @{
        id = 'prof-m365'; name = 'Microsoft 365'; state = 'enabled'; trafficForwardingType = 'm365'; isCustomProfile = $false
        assignmentRules = @{ assignments = @{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' } }
        policies = @(@{ id = 'link-exo'; state = 'enabled'; policyName = 'Exchange Online' })
    }
    function New-Row {
        param($Internet = $script:Internet, $M365 = $script:M365Sibling, $Onboarded = $true)
        @{
            id               = 'networkAccess'
            onboardingStatus = $(if ($Onboarded) { 'onboarded' } else { 'notOnboarded' })
            onboarded        = $Onboarded
            signalingStatus  = 'enabled'
            profiles         = @($Internet, $M365) | Where-Object { $_ }
        }
    }
    function New-Enumerated {
        param($Groups = @(), $Users = @(), $Devices = @())
        @{ assignments = @{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsEnumeratedMembership'; users = @($Users); groups = @($Groups); devices = @($Devices) } }
    }
    function New-ItemVars {
        param([string]$ProfileState, [string]$AssignTo, [string]$CustomGroup)
        [PSCustomObject]@{
            profileState = $ProfileState
            assignTo     = $AssignTo
            customGroup  = $CustomGroup
        }
    }
}

Describe 'Get-CIPPBaselineGlobalSecureAccessInternetProfileState' {
    BeforeAll {
        $script:GroupsCache = @(
            @{ id = 'g-pilot'; displayName = 'GSA Pilot' }
            @{ id = 'g-it'; displayName = 'IT' }
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

    It 'grades the Internet profile (not its Microsoft 365 sibling) compliant in default mode' {
        $P = Get-CIPPBaselineGlobalSecureAccessInternetProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars) }) -TenantFilter $script:Tenant
        (Get-Verdict -Expected $P.Expected -Current $P.Current).Count | Should -Be 0
        $P.Expected.PSObject.Properties.Name | Should -Be @('profileState', 'policyLinksEnabled', 'assignedToAllUsers')
        $P.Current.profileState | Should -Be 'enabled'
    }

    It 'grades drift on a disabled Internet profile with a disabled link and a scoped assignment' {
        $Internet = $script:Internet.Clone()
        $Internet.state = 'disabled'
        $Internet.policies = @(@{ id = 'link-acq'; state = 'disabled'; policyName = 'Default Acquire' })
        $Internet.assignmentRules = New-Enumerated -Groups @(@{ id = 'g-hand' })
        $script:Row = New-Row -Internet $Internet
        $P = Get-CIPPBaselineGlobalSecureAccessInternetProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars) }) -TenantFilter $script:Tenant
        $Differences = Get-Verdict -Expected $P.Expected -Current $P.Current
        @($Differences.Property | Sort-Object) | Should -Be @('assignedToAllUsers', 'policyLinksEnabled', 'profileState')
    }

    It 'grades customGroup and DoNotAssign against the Internet profile assignmentRules' {
        $Internet = $script:Internet.Clone()
        $Internet.assignmentRules = New-Enumerated -Groups @(@{ id = 'g-pilot' })
        $script:Row = New-Row -Internet $Internet
        $P = Get-CIPPBaselineGlobalSecureAccessInternetProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -AssignTo 'customGroup' -CustomGroup 'GSA Pilot') }) -TenantFilter $script:Tenant
        (Get-Verdict -Expected $P.Expected -Current $P.Current).Count | Should -Be 0

        $Internet.assignmentRules = New-Enumerated
        $script:Row = New-Row -Internet $Internet
        $P = Get-CIPPBaselineGlobalSecureAccessInternetProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars -AssignTo 'DoNotAssign') }) -TenantFilter $script:Tenant
        $P.Expected.PSObject.Properties.Name | Should -Be @('profileState', 'policyLinksEnabled', 'assignedToAllUsers', 'nobodyAssigned')
        (Get-Verdict -Expected $P.Expected -Current $P.Current).Count | Should -Be 0
    }

    It 'grades a profile with no policy links as enabled on the links property' {
        $Internet = $script:Internet.Clone()
        $Internet.policies = @()
        $script:Row = New-Row -Internet $Internet
        $P = Get-CIPPBaselineGlobalSecureAccessInternetProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars) }) -TenantFilter $script:Tenant
        $P.Current.policyLinksEnabled | Should -BeTrue
        (Get-Verdict -Expected $P.Expected -Current $P.Current).Count | Should -Be 0
    }

    It 'reports No Data when only the Microsoft 365 profile exists - the Internet profile has not been created' {
        $script:Row = New-Row -Internet $null
        $P = Get-CIPPBaselineGlobalSecureAccessInternetProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars) }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.NoDataReason | Should -BeLike '*Internet traffic forwarding profile has not been created*'
    }

    It 'names the onboarding prerequisite for a tenant that is not onboarded' {
        $script:Row = New-Row -Onboarded $false
        $P = Get-CIPPBaselineGlobalSecureAccessInternetProfileState -Item ([PSCustomObject]@{ Variables = (New-ItemVars) }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.NoDataReason | Should -BeLike '*not onboarded to Global Secure Access*'
    }
}

Describe 'Invoke-CIPPBaselineGlobalSecureAccessInternetProfile' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock New-GraphPostRequest { }
        $script:LiveInternetState = 'enabled'
        $script:LiveInternetType = 'AllMembership'
        $script:LiveAssignedGroups = @()
        Mock New-GraphGetRequest {
            switch -Wildcard ($uri) {
                '*networkAccess/forwardingProfiles*' {
                    @(
                        [PSCustomObject]@{
                            id = 'prof-inet'; name = 'Internet'; state = $script:LiveInternetState; trafficForwardingType = 'internet'; isCustomProfile = $false
                            policies        = @(
                                [PSCustomObject]@{ id = 'link-acq'; state = 'enabled' }
                                [PSCustomObject]@{ id = 'link-byp'; state = 'enabled' }
                            )
                            assignmentRules = [PSCustomObject]@{
                                assignments           = if ($script:LiveInternetType -eq 'AllMembership') {
                                    [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' }
                                } else {
                                    [PSCustomObject]@{
                                        '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsEnumeratedMembership'
                                        users         = @(); devices = @()
                                        groups        = @($script:LiveAssignedGroups | ForEach-Object { [PSCustomObject]@{ id = $_ } })
                                    }
                                }
                                devicePropertyFilters = [PSCustomObject]@{ platforms = 'windows,macOS,android,iOS' }
                            }
                        }
                        [PSCustomObject]@{
                            id = 'prof-m365'; name = 'Microsoft 365'; state = 'enabled'; trafficForwardingType = 'm365'; isCustomProfile = $false
                            policies        = @(); assignmentRules = [PSCustomObject]@{ assignments = [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' } }
                        }
                    )
                }
                '*groups?*' {
                    @(
                        [PSCustomObject]@{ id = 'g-pilot'; displayName = 'GSA Pilot' }
                    )
                }
                default { throw "unexpected uri: $uri" }
            }
        }
    }

    It 'reports Changed=false without writing anything on a fully configured tenant' {
        $Result = Invoke-CIPPBaselineGlobalSecureAccessInternetProfile -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $null
        $Result.Changed | Should -BeFalse
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
    }

    It 'enables a disabled Internet profile, its disabled link and the all-users assignment - writing the Internet profile, never the Microsoft 365 sibling' {
        $script:LiveInternetState = 'disabled'
        $script:LiveInternetType = 'EnumeratedMembership'
        Mock New-GraphGetRequest {
            @(
                [PSCustomObject]@{
                    id = 'prof-inet'; name = 'Internet'; state = $script:LiveInternetState; trafficForwardingType = 'internet'; isCustomProfile = $false
                    policies        = @(
                        [PSCustomObject]@{ id = 'link-acq'; state = 'disabled' }
                        [PSCustomObject]@{ id = 'link-byp'; state = 'enabled' }
                    )
                    assignmentRules = [PSCustomObject]@{
                        assignments           = [PSCustomObject]@{
                            '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsEnumeratedMembership'
                            users         = @(); devices = @(); groups = @()
                        }
                        devicePropertyFilters = [PSCustomObject]@{ platforms = 'windows,macOS,android,iOS' }
                    }
                }
                [PSCustomObject]@{
                    id = 'prof-m365'; name = 'Microsoft 365'; state = 'enabled'; trafficForwardingType = 'm365'; isCustomProfile = $false
                    policies        = @(); assignmentRules = [PSCustomObject]@{ assignments = [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' } }
                }
            )
        }
        $Result = Invoke-CIPPBaselineGlobalSecureAccessInternetProfile -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $null
        $Result | Should -BeNullOrEmpty
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*networkAccess/forwardingProfiles/prof-inet' -and $body -like '*"state":"enabled"*' }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*forwardingProfiles/prof-inet/policies/link-acq*' -and $body -like '*"state":"enabled"*' }
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*networkAccess/forwardingProfiles/prof-inet' -and $body -like '*forwardingProfileAssignmentsAllMembership*' }
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*prof-m365*' }
    }

    It 'scopes the Internet profile to the configured group in the portal-exact body shape' {
        $Remediate = [PSCustomObject]@{ assignTo = 'customGroup'; customGroup = 'GSA Pilot' }
        $Result = Invoke-CIPPBaselineGlobalSecureAccessInternetProfile -Remediate $Remediate -TenantFilter $script:Tenant -Current $null
        $Result | Should -BeNullOrEmpty
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*networkAccess/forwardingProfiles/prof-inet' -and $body -like '*assignmentRules*devicePropertyFilters*platforms*"windows,macOS,android,iOS"*assignments*EnumeratedMembership*g-pilot*' }
    }

    It 'throws when the Internet profile has not been created, even though the Microsoft 365 profile exists' {
        Mock New-GraphGetRequest {
            @([PSCustomObject]@{
                    id = 'prof-m365'; name = 'Microsoft 365'; state = 'enabled'; trafficForwardingType = 'm365'; isCustomProfile = $false
                    policies        = @(); assignmentRules = [PSCustomObject]@{ assignments = [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' } }
                })
        }
        { Invoke-CIPPBaselineGlobalSecureAccessInternetProfile -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $null } | Should -Throw '*Internet traffic forwarding profile was not found*'
    }
}
