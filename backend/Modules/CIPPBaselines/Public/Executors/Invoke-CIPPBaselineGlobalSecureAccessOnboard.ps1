function Invoke-CIPPBaselineGlobalSecureAccessOnboard {
    <#
    .SYNOPSIS
        GlobalSecureAccessOnboard executor: onboards the tenant to Global Secure Access.
    .DESCRIPTION
        Reads the LIVE onboarding status - never the cache - so a stale cache can never
        trigger a bogus POST, then starts onboarding for a tenant that is not onboarded
        and waits out the asynchronous tail (15s x 12 reads, the same window the packaged
        compliant-network standard uses). Onboarding is a one-way door: there is no
        offboard action, so this executor never attempts to reverse it. A tenant that is
        still settling when the window ends is left to the next run's verification, and
        a failed onboarding surfaces the API's own error message instead of a re-POST.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Remediate, $TenantFilter, $Current)

    $Graph = 'https://graph.microsoft.com/beta'
    $Status = New-GraphGetRequest -uri "$Graph/networkAccess/tenantStatus" -tenantid $TenantFilter -AsApp $true

    if ($Status.onboardingStatus -eq 'onboarded') {
        # The engine only reaches this on a stale cache or a forced run. The cache the
        # compare graded from disagrees with reality, so recollect it and let the next
        # run agree; the engine itself does not refresh after a no-write outcome.
        if ($Current.onboarded -ne $true) {
            $Collector = Get-CIPPBaselineCommand -Name 'Set-CIPPDBCacheNetworkAccess'
            if ($Collector) {
                try { $null = & $Collector -TenantFilter $TenantFilter } catch { Write-Information "Baselines: NetworkAccess cache refresh on $TenantFilter failed: $($_.Exception.Message)" }
            }
        }
        return [PSCustomObject]@{ Changed = $false }
    }

    if ($Status.onboardingStatus -eq 'onboardingErrorOccurred') { throw "Global Secure Access onboarding failed earlier: $($Status.onboardingErrorMessage)" }

    # Never double-POST: a tenant that is already onboarding only needs the wait.
    if ($Status.onboardingStatus -ne 'onboardingInProgress') {
        $null = New-GraphPostRequest -uri "$Graph/networkAccess/microsoft.graph.networkaccess.onboard" -tenantid $TenantFilter -type POST -body '{}' -AsApp $true
    }
    $Attempts = 0
    do {
        Start-Sleep -Seconds 15
        $Attempts++
        $Status = New-GraphGetRequest -uri "$Graph/networkAccess/tenantStatus" -tenantid $TenantFilter -AsApp $true
    } while ($Status.onboardingStatus -eq 'onboardingInProgress' -and $Attempts -lt 12)

    if ($Status.onboardingStatus -eq 'onboardingErrorOccurred') { throw "Global Secure Access onboarding failed earlier: $($Status.onboardingErrorMessage)" }
    if ($Status.onboardingStatus -eq 'onboarded') {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message 'Onboarded the tenant to Global Secure Access.' -Sev 'Info'
    } else {
        Write-LogMessage -API 'Baselines' -tenant $TenantFilter -message "Global Secure Access onboarding is still '$($Status.onboardingStatus)'; the next run re-verifies it." -Sev 'Info'
    }
}
