# GlobalSecureAccessSignaling: the signaling prepare hook. Signaling cannot be graded or
# written until the tenant is onboarded - every networkAccess path except tenantStatus
# answers 403 - so the hook must name the prerequisite instead of letting Graph's ambiguous
# 403 (missing app permission or missing onboarding?) speak for it.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) }

    . (Join-Path $Baselines 'PrepareHooks/Get-CIPPBaselineGlobalSecureAccessSignalingState.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 25 | ConvertFrom-Json } }
}

Describe 'Get-CIPPBaselineGlobalSecureAccessSignalingState' {
    It 'grades the cached signaling status of an onboarded tenant' {
        Mock New-CIPPDbRequest { @(@{ id = 'networkAccess'; onboardingStatus = 'onboarded'; onboarded = $true; signalingStatus = 'enabled'; profiles = @() } | ConvertTo-Cached) }
        $P = Get-CIPPBaselineGlobalSecureAccessSignalingState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        $P.Current.signalingStatus | Should -Be 'enabled'
        $P.NoDataReason | Should -BeNullOrEmpty
    }

    It 'carries a disabled signaling status so the compare grades it as drift' {
        Mock New-CIPPDbRequest { @(@{ id = 'networkAccess'; onboardingStatus = 'onboarded'; onboarded = $true; signalingStatus = 'disabled'; profiles = @() } | ConvertTo-Cached) }
        $P = Get-CIPPBaselineGlobalSecureAccessSignalingState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        $P.Current.signalingStatus | Should -Be 'disabled'
        $P.NoDataReason | Should -BeNullOrEmpty
    }

    It 'names the onboarding prerequisite for a tenant that is not onboarded, instead of grading null signaling as drift' {
        Mock New-CIPPDbRequest { @(@{ id = 'networkAccess'; onboardingStatus = 'notOnboarded'; onboarded = $false; signalingStatus = $null; profiles = @() } | ConvertTo-Cached) }
        $P = Get-CIPPBaselineGlobalSecureAccessSignalingState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.NoDataReason | Should -BeLike '*not onboarded to Global Secure Access*Onboard Global Secure Access*'
    }

    It 'returns plain No Data when the NetworkAccess cache was never collected' {
        Mock New-CIPPDbRequest { @() }
        $P = Get-CIPPBaselineGlobalSecureAccessSignalingState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.NoDataReason | Should -BeNullOrEmpty
    }
}
