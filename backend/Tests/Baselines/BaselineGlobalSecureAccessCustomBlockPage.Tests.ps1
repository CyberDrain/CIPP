# GlobalSecureAccessCustomBlockPage: the custom block page prepare hook. The block page
# is a singleton setting administrators deliberately edit, so it is graded live - the
# same reasoning as the signaling standard - and its remediation is fully declarative
# through the documented settings PATCH, so there is no executor to test.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }

    . (Join-Path $Baselines 'PrepareHooks/Get-CIPPBaselineGlobalSecureAccessCustomBlockPageState.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
}

Describe 'Get-CIPPBaselineGlobalSecureAccessCustomBlockPageState' {
    BeforeEach {
        $script:LiveStatus = 'onboarded'
        $script:LivePageState = 'disabled'
        $script:LiveBody = ''
        Mock New-GraphGetRequest {
            switch -Wildcard ($uri) {
                '*networkAccess/tenantStatus' { [PSCustomObject]@{ onboardingStatus = $script:LiveStatus } }
                '*settings/customBlockPage' { [PSCustomObject]@{ state = $script:LivePageState; configuration = [PSCustomObject]@{ '@odata.type' = '#microsoft.graph.networkaccess.markdownBlockMessageConfiguration'; body = $script:LiveBody } } }
                default { throw "unexpected uri: $uri" }
            }
        }
    }

    It 'grades a configured block page compliant: enabled with the exact message' {
        $script:LivePageState = 'enabled'
        $script:LiveBody = 'Blocked by IT. [Contact the help desk](https://help.example.com)'
        $Vars = [PSCustomObject]@{ state = 'enabled'; blockMessage = 'Blocked by IT. [Contact the help desk](https://help.example.com)' }
        $P = Get-CIPPBaselineGlobalSecureAccessCustomBlockPageState -Item ([PSCustomObject]@{ Variables = $Vars }) -TenantFilter $script:Tenant
        $P.Expected.PSObject.Properties.Name | Should -Be @('state', 'blockMessage')
        $P.Current.state | Should -Be 'enabled'
        $P.Current.blockMessage | Should -Be $Vars.blockMessage
        $P.NoDataReason | Should -BeNullOrEmpty
    }

    It 'grades drift when the live message differs or the page is disabled' {
        $Vars = [PSCustomObject]@{ state = 'enabled'; blockMessage = 'Blocked by IT.' }
        $P = Get-CIPPBaselineGlobalSecureAccessCustomBlockPageState -Item ([PSCustomObject]@{ Variables = $Vars }) -TenantFilter $script:Tenant
        # live: disabled, empty body - both properties drift
        $P.Current.state | Should -Be 'disabled'
        $P.Current.blockMessage | Should -Be ''
    }

    It 'grades only the state when the desired state is disabled - the message expresses no opinion' {
        $script:LivePageState = 'enabled'
        $script:LiveBody = 'Anything the admin left behind'
        $Vars = [PSCustomObject]@{ state = 'disabled' }
        $P = Get-CIPPBaselineGlobalSecureAccessCustomBlockPageState -Item ([PSCustomObject]@{ Variables = $Vars }) -TenantFilter $script:Tenant
        $P.Expected.PSObject.Properties.Name | Should -Be @('state')
        $P.Expected.state | Should -Be 'disabled'
    }

    It 'applies the enabled default and refuses an enabled page with no message' {
        $P = Get-CIPPBaselineGlobalSecureAccessCustomBlockPageState -Item ([PSCustomObject]@{ Variables = [PSCustomObject]@{} }) -TenantFilter $script:Tenant
        $P.ConfigError | Should -BeTrue
        $P.NoDataReason | Should -BeLike '*no message*'
    }

    It 'names the onboarding prerequisite for a tenant that is not onboarded' {
        $script:LiveStatus = 'notOnboarded'
        $Vars = [PSCustomObject]@{ state = 'enabled'; blockMessage = 'Blocked by IT.' }
        $P = Get-CIPPBaselineGlobalSecureAccessCustomBlockPageState -Item ([PSCustomObject]@{ Variables = $Vars }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.NoDataReason | Should -BeLike '*not onboarded to Global Secure Access*'
        Should -Invoke New-GraphGetRequest -Times 0 -Exactly -ParameterFilter { $uri -like '*customBlockPage*' }
    }

    It 'reports No Data with the reason when the live block page read fails' {
        Mock New-GraphGetRequest {
            switch -Wildcard ($uri) {
                '*networkAccess/tenantStatus' { [PSCustomObject]@{ onboardingStatus = 'onboarded' } }
                '*settings/customBlockPage' { throw '403 Forbidden' }
                default { throw "unexpected uri: $uri" }
            }
        }
        $Vars = [PSCustomObject]@{ state = 'enabled'; blockMessage = 'Blocked by IT.' }
        $P = Get-CIPPBaselineGlobalSecureAccessCustomBlockPageState -Item ([PSCustomObject]@{ Variables = $Vars }) -TenantFilter $script:Tenant
        $P.Current | Should -BeNullOrEmpty
        $P.NoDataReason | Should -BeLike '*block page*403 Forbidden*'
    }
}
