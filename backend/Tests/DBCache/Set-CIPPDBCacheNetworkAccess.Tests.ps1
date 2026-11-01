# Set-CIPPDBCacheNetworkAccess: one row per tenant with the GSA onboarding status, the
# forwarding profiles (with policy groups, the profile app's assignment flag and - for the
# Microsoft 365 profile only - the group assignments behind that flag) and the CA signaling
# setting. The assignments are what GlobalSecureAccessM365Profile grades in CustomGroups
# mode, so the cache must actually contain them.

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
                        [PSCustomObject]@{ id = 'prof-m365'; name = 'Microsoft 365'; state = 'enabled'; trafficForwardingType = 'm365'; isCustomProfile = $false; servicePrincipal = [PSCustomObject]@{ id = 'sp-m365' }; policies = @([PSCustomObject]@{ id = 'link-1'; state = 'enabled'; policy = [PSCustomObject]@{ name = 'Exchange Online' } }) }
                        [PSCustomObject]@{ id = 'prof-priv'; name = 'Private'; state = 'disabled'; trafficForwardingType = 'private'; isCustomProfile = $false; servicePrincipal = [PSCustomObject]@{ id = 'sp-priv' }; policies = @() }
                    )
                }
                '*servicePrincipals/sp-m365*' {
                    if ($script:M365SpFails) { throw '403 Forbidden' }
                    [PSCustomObject]@{
                        appRoleAssignmentRequired = $false
                        appRoleAssignments        = @(
                            [PSCustomObject]@{ principalId = 'g-pilot'; principalDisplayName = 'GSA Pilot' }
                            [PSCustomObject]@{ principalId = 'g-it'; principalDisplayName = 'IT' }
                        )
                    }
                }
                '*servicePrincipals/sp-priv*' { [PSCustomObject]@{ appRoleAssignmentRequired = $true } }
                '*networkAccess/settings/conditionalAccess' { [PSCustomObject]@{ signalingStatus = 'enabled' } }
                default { throw "unexpected uri: $uri" }
            }
        }
    }

    It 'caches the profile list with the assignment flag, and the group assignments for the Microsoft 365 profile only' {
        Set-CIPPDBCacheNetworkAccess -TenantFilter 'contoso.onmicrosoft.com'

        $Row = $script:Written | Where-Object { $_.id -eq 'networkAccess' }
        $Row.onboarded | Should -BeTrue
        $Row.signalingStatus | Should -Be 'enabled'
        @($Row.profiles).Count | Should -Be 2
        $M365 = $Row.profiles | Where-Object { $_.trafficForwardingType -eq 'm365' }
        $M365.appRoleAssignmentRequired | Should -BeFalse
        @($M365.assignments).Count | Should -Be 2
        @($M365.assignments.principalDisplayName) | Should -Be @('GSA Pilot', 'IT')
        $Private = $Row.profiles | Where-Object { $_.trafficForwardingType -eq 'private' }
        $Private.appRoleAssignmentRequired | Should -BeTrue
        $Private.assignments | Should -BeNullOrEmpty
        # Only the Microsoft 365 profile's SP read expands assignments; the others stay cheap.
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*servicePrincipals/sp-m365*' -and $uri -like '*$expand=appRoleAssignments*' }
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*servicePrincipals/sp-priv*' -and $uri -notlike '*$expand=appRoleAssignments*' }
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

    It 'still writes the row, with no assignments and a warning, when the Microsoft 365 SP read fails' {
        $script:M365SpFails = $true
        Set-CIPPDBCacheNetworkAccess -TenantFilter 'contoso.onmicrosoft.com'

        $Row = $script:Written | Where-Object { $_.id -eq 'networkAccess' }
        $M365 = $Row.profiles | Where-Object { $_.trafficForwardingType -eq 'm365' }
        $M365.assignments | Should -BeNullOrEmpty
        $M365.appRoleAssignmentRequired | Should -BeNullOrEmpty
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $message -like '*Could not read the app behind forwarding profile*Microsoft 365*' }
    }
}
