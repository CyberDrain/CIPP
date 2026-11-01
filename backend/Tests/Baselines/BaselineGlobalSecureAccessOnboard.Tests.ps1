# GlobalSecureAccessOnboard: the onboarding executor's state machine. Onboarding is a one-way
# door with an asynchronous tail, so the executor must never double-POST, never swallow the
# API's onboarding error message, and never report a settling tenant as broken.

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Baselines = Join-Path $script:RepoRoot 'Modules/CIPPBaselines/Public'

    function New-GraphGetRequest { param($uri, $tenantid, $AsApp) }
    function New-GraphPostRequest { param($uri, $tenantid, $type, $body, $AsApp) }
    function Write-LogMessage { param($API, $tenant, $message, $Sev, $LogData) }
    function Set-CIPPDBCacheNetworkAccess { param($TenantFilter) }

    . (Join-Path $Baselines 'Helpers/Get-CIPPBaselineCommand.ps1')
    . (Join-Path $Baselines 'Executors/Invoke-CIPPBaselineGlobalSecureAccessOnboard.ps1')

    $script:Tenant = 'contoso.onmicrosoft.com'
    function ConvertTo-Cached { param([Parameter(ValueFromPipeline = $true)]$InputObject) process { $InputObject | ConvertTo-Json -Depth 25 | ConvertFrom-Json } }
}

Describe 'Invoke-CIPPBaselineGlobalSecureAccessOnboard' {
    BeforeEach {
        Mock Start-Sleep { }
        Mock Write-LogMessage { }
        Mock Set-CIPPDBCacheNetworkAccess { }
        # The status the live tenantStatus call reports once any simulated settling is done.
        $script:LiveStatus = 'onboarded'
        $script:LiveError = $null
        # How many tenantStatus reads answer 'onboardingInProgress' before LiveStatus applies.
        $script:PendingPolls = 0
        Mock New-GraphGetRequest {
            if ($script:PendingPolls -gt 0) {
                $script:PendingPolls--
                [PSCustomObject]@{ onboardingStatus = 'onboardingInProgress' }
            } else {
                [PSCustomObject]@{ onboardingStatus = $script:LiveStatus; onboardingErrorMessage = $script:LiveError }
            }
        }
        # Starting onboarding takes minutes: the POST moves the tenant INTO progress, and
        # completion lands on LiveStatus once the settling reads are exhausted.
        Mock New-GraphPostRequest {
            if ($uri -like '*networkaccess.onboard') { $script:LiveStatus = 'onboarded'; $script:PendingPolls = 1 }
        }
    }

    It 'reports Changed=false without POSTing or refreshing anything when the tenant is already onboarded' {
        $Result = Invoke-CIPPBaselineGlobalSecureAccessOnboard -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current (@{ onboarded = $true } | ConvertTo-Cached)
        $Result.Changed | Should -BeFalse
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
        Should -Invoke Set-CIPPDBCacheNetworkAccess -Times 0 -Exactly
    }

    It 'self-heals a stale cache: no POST, but the NetworkAccess cache is refreshed so the next run grades compliant' {
        $Result = Invoke-CIPPBaselineGlobalSecureAccessOnboard -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current $null
        $Result.Changed | Should -BeFalse
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
        Should -Invoke Set-CIPPDBCacheNetworkAccess -Times 1 -Exactly
    }

    It 'onboards a not-onboarded tenant: one POST with an empty body, polls to completion, no cache refresh of its own' {
        $script:LiveStatus = 'notOnboarded'
        $Result = Invoke-CIPPBaselineGlobalSecureAccessOnboard -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current (@{ onboarded = $false } | ConvertTo-Cached)
        $Result | Should -BeNullOrEmpty
        Should -Invoke New-GraphPostRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*networkAccess/microsoft.graph.networkaccess.onboard' -and $type -eq 'POST' -and $body -eq '{}' -and $AsApp -eq $true }
        Should -Invoke New-GraphGetRequest -Times 3 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $message -like '*Onboarded the tenant to Global Secure Access*' }
        Should -Invoke Set-CIPPDBCacheNetworkAccess -Times 0 -Exactly
    }

    It 'never double-POSTs a tenant that is already onboarding, and observes its completion' {
        $script:PendingPolls = 2
        $Result = Invoke-CIPPBaselineGlobalSecureAccessOnboard -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current (@{ onboarded = $false } | ConvertTo-Cached)
        $Result | Should -BeNullOrEmpty
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $message -like '*Onboarded the tenant to Global Secure Access*' }
    }

    It 'treats a tenant still settling after the polling window as pending, not broken: no throw, no POST, no error log' {
        $script:LiveStatus = 'onboardingInProgress'
        $script:PendingPolls = 99
        { $Result = Invoke-CIPPBaselineGlobalSecureAccessOnboard -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current (@{ onboarded = $false } | ConvertTo-Cached); $Result | Should -BeNullOrEmpty } | Should -Not -Throw
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
        Should -Invoke New-GraphGetRequest -Times 13 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $message -like '*still*' -and $Sev -eq 'Info' }
        Should -Invoke Write-LogMessage -Times 0 -Exactly -ParameterFilter { $Sev -eq 'Error' }
    }

    It 'surfaces the API onboarding error instead of re-POSTing over it' {
        $script:LiveStatus = 'onboardingErrorOccurred'
        $script:LiveError = 'the tenant is not licensed for Global Secure Access'
        { Invoke-CIPPBaselineGlobalSecureAccessOnboard -Remediate ([PSCustomObject]@{}) -TenantFilter $script:Tenant -Current (@{ onboarded = $false } | ConvertTo-Cached) } | Should -Throw '*the tenant is not licensed for Global Secure Access*'
        Should -Invoke New-GraphPostRequest -Times 0 -Exactly
    }
}
