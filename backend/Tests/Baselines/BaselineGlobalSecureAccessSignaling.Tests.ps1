# GlobalSecureAccessSignaling: the signaling prepare hook. Signaling is a single toggle
# administrators flip deliberately, so the hook grades the LIVE setting - a cache read
# would report compliant for a tenant that changed underneath the last collection
# (the false-compliant this suite is the regression test for). Every networkAccess path
# except tenantStatus answers 403 until the tenant is onboarded, so the live tenant
# status is read first and a tenant that is not onboarded gets the prerequisite named
# instead of Graph's ambiguous 403 (missing app permission or missing onboarding?).

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    # New-CIPPDbRequest is deliberately NOT stubbed: this hook must never read the cache.
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }

    . (Join-Path $Baselines 'PrepareHooks/Get-CIPPBaselineGlobalSecureAccessSignalingState.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Get-CIPPBaselineGlobalSecureAccessSignalingState' {
    BeforeEach {
        $script:LiveStatus = 'onboarded'
        $script:LiveSignaling = 'enabled'
        Mock New-GraphGetRequest {
            switch -Wildcard ($uri) {
                '*networkAccess/tenantStatus' { [PSCustomObject]@{ onboardingStatus = $script:LiveStatus } }
                '*networkAccess/settings/conditionalAccess' { [PSCustomObject]@{ signalingStatus = $script:LiveSignaling } }
                default { throw "unexpected uri: $uri" }
            }
        }
    }

    It 'grades the LIVE signaling status of an onboarded tenant' {
        $P = Get-CIPPBaselineGlobalSecureAccessSignalingState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        $P.Current.signalingStatus | Should -Be 'enabled'
        $P.NoDataReason | Should -BeNullOrEmpty
    }

    It 'carries the live disabled status so a tenant flipped after the last cache collection grades as drift' {
        $script:LiveSignaling = 'disabled'
        $P = Get-CIPPBaselineGlobalSecureAccessSignalingState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        $P.Current.signalingStatus | Should -Be 'disabled'
        $P.NoDataReason | Should -BeNullOrEmpty
    }

    It 'names the onboarding prerequisite for a tenant that is not onboarded, instead of grading Graph 403 as drift' {
        $script:LiveStatus = 'notOnboarded'
        $P = Get-CIPPBaselineGlobalSecureAccessSignalingState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.NoDataReason | Should -BeLike '*not onboarded to Global Secure Access*Onboard Global Secure Access*'
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*settings/conditionalAccess' }
    }

    It 'treats a tenant still onboarding as not onboarded' {
        $script:LiveStatus = 'onboardingInProgress'
        $P = Get-CIPPBaselineGlobalSecureAccessSignalingState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.NoDataReason | Should -BeLike '*not onboarded to Global Secure Access*'
    }

    It 'reports No Data with the reason when the live signaling read fails, rather than grading anything' {
        Mock New-GraphGetRequest {
            switch -Wildcard ($uri) {
                '*networkAccess/tenantStatus' { [PSCustomObject]@{ onboardingStatus = 'onboarded' } }
                '*networkAccess/settings/conditionalAccess' { throw '403 Forbidden' }
                default { throw "unexpected uri: $uri" }
            }
        }
        $P = Get-CIPPBaselineGlobalSecureAccessSignalingState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.NoDataReason | Should -BeLike '*signaling setting*403 Forbidden*'
    }
}
