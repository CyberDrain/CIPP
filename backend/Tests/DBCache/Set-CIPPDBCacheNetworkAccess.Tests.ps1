# Set-CIPPDBCacheNetworkAccess: one row per tenant with the GSA onboarding status, the
# forwarding profiles (with policy groups, the legacy profile-app assignment flag, the
# assignmentRules the portal's User and device assignments blade actually reads and
# writes, and the branch associations) and the CA signaling setting.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheNetworkAccess.ps1')

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) $true }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) $script:Written = @($Data); $script:WroteEmpty = $ClearOnEmpty.IsPresent }
}

Describe 'Set-CIPPDBCacheNetworkAccess' {
    BeforeEach {
        $script:Written = $null
        $script:WroteEmpty = $false
        $script:LiveStatus = 'onboarded'
        $script:M365SpFails = $false
        Mock Write-LogMessage { }
        Mock New-GraphGetRequest {
            switch -Wildcard ($uri) {
                '*networkAccess/tenantStatus' { [PSCustomObject]@{ onboardingStatus = $script:LiveStatus } }
                '*networkAccess/forwardingProfiles*' {
                    @(
                        [PSCustomObject]@{
                            id = 'prof-m365'; name = 'Microsoft 365'; state = 'enabled'; trafficForwardingType = 'm365'; isCustomProfile = $false
                            servicePrincipal = [PSCustomObject]@{ id = 'sp-m365' }
                            policies         = @([PSCustomObject]@{ id = 'link-1'; state = 'enabled'; policy = [PSCustomObject]@{ name = 'Exchange Online' } })
                            associations     = @()
                            assignmentRules  = [PSCustomObject]@{
                                assignments = [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership' }
                            }
                        }
                        [PSCustomObject]@{
                            id = 'prof-priv'; name = 'Private'; state = 'disabled'; trafficForwardingType = 'private'; isCustomProfile = $false
                            servicePrincipal = [PSCustomObject]@{ id = 'sp-priv' }
                            policies         = @()
                            associations     = @([PSCustomObject]@{ '@odata.type' = '#microsoft.graph.associatedBranch'; branchId = 'b-1' })
                            assignmentRules  = [PSCustomObject]@{
                                assignments = [PSCustomObject]@{
                                    '@odata.type' = '#microsoft.graph.networkaccess.forwardingProfileAssignmentsEnumeratedMembership'
                                    users         = @()
                                    groups        = @([PSCustomObject]@{ id = 'g-pilot' })
                                    devices       = @()
                                }
                            }
                        }
                    )
                }
                '*servicePrincipals/sp-m365*' {
                    if ($script:M365SpFails) { throw '403 Forbidden' }
                    [PSCustomObject]@{ appRoleAssignmentRequired = $false }
                }
                '*servicePrincipals/sp-priv*' { [PSCustomObject]@{ appRoleAssignmentRequired = $true } }
                '*networkAccess/settings/conditionalAccess' { [PSCustomObject]@{ signalingStatus = 'enabled' } }
                default { throw "unexpected uri: $uri" }
            }
        }
    }

    It 'caches the profiles with the legacy flag, the assignmentRules and the associations verbatim' {
        Set-CIPPDBCacheNetworkAccess -TenantFilter 'contoso.onmicrosoft.com'

        $Row = $script:Written | Where-Object { $_.id -eq 'networkAccess' }
        $Row.onboarded | Should -BeTrue
        $Row.signalingStatus | Should -Be 'enabled'
        @($Row.profiles).Count | Should -Be 2
        $M365 = $Row.profiles | Where-Object { $_.trafficForwardingType -eq 'm365' }
        $M365.appRoleAssignmentRequired | Should -BeFalse
        $M365.assignmentRules.assignments.'@odata.type' | Should -Be '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership'
        $Private = $Row.profiles | Where-Object { $_.trafficForwardingType -eq 'private' }
        $Private.appRoleAssignmentRequired | Should -BeTrue
        $Private.assignmentRules.assignments.'@odata.type' | Should -Be '#microsoft.graph.networkaccess.forwardingProfileAssignmentsEnumeratedMembership'
        @($Private.assignmentRules.assignments.groups).Count | Should -Be 1
        $Private.assignmentRules.assignments.groups[0].id | Should -Be 'g-pilot'
        @($Private.associations).Count | Should -Be 1
        $Private.associations[0].branchId | Should -Be 'b-1'
        @($M365.associations).Count | Should -Be 0
        # The SP read stays a cheap flag read - the appRoleAssignments expand was the legacy
        # enterprise-app surface, which the portal's assignment blade does not read.
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*servicePrincipals*' -and $uri -like '*$expand*' }
    }

    It 'records a not-onboarded tenant from the tenant status alone - every other networkAccess path answers 403' {
        $script:LiveStatus = 'notOnboarded'
        Set-CIPPDBCacheNetworkAccess -TenantFilter 'contoso.onmicrosoft.com'

        $Row = $script:Written | Where-Object { $_.id -eq 'networkAccess' }
        $Row.onboarded | Should -BeFalse
        @($Row.profiles).Count | Should -Be 0
        $Row.signalingStatus | Should -BeNullOrEmpty
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly
    }

    It 'writes an empty row for an unlicensed tenant so the standard skips on license, not on missing data' {
        Mock Test-CIPPStandardLicense { $false }
        Set-CIPPDBCacheNetworkAccess -TenantFilter 'contoso.onmicrosoft.com'

        @($script:Written).Count | Should -Be 0
        $script:WroteEmpty | Should -BeTrue
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly
    }

    It 'still writes the row, with no legacy flag and a warning, when the SP read fails - assignmentRules come from the profile itself' {
        $script:M365SpFails = $true
        Set-CIPPDBCacheNetworkAccess -TenantFilter 'contoso.onmicrosoft.com'

        $Row = $script:Written | Where-Object { $_.id -eq 'networkAccess' }
        $M365 = $Row.profiles | Where-Object { $_.trafficForwardingType -eq 'm365' }
        $M365.appRoleAssignmentRequired | Should -BeNullOrEmpty
        $M365.assignmentRules.assignments.'@odata.type' | Should -Be '#microsoft.graph.networkaccess.forwardingProfileAssignmentsAllMembership'
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $message -like '*Could not read the app behind forwarding profile*Microsoft 365*' }
    }
}
