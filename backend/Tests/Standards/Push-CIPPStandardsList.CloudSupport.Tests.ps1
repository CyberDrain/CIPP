# Classic standards a tenant's cloud does not support (redanthrax/CIPP#4) are not queued for that tenant: the compare
# field says why and one informational line is logged per run. A Commercial tenant's list is returned unchanged.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-CIPPStandardsList.ps1' -File | Select-Object -First 1 -ExpandProperty FullName
    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPCloudFeatureSupport.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Test-CIPPCloudFeatureSupport.ps1')
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-CIPPStandard.ps1' -File | Select-Object -First 1 -ExpandProperty FullName
    . $FunctionPath

    function Get-CIPPTenantRequestCloud { param($TenantFilter) }
    function Get-CIPPStandards { param($TenantFilter, $runManually, $TemplateId) }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset) }
    function Set-CIPPStandardsCompareField { param($TenantFilter, $BulkFields) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Test-CIPPRerun { param($Type, $Tenant, $API, $BaseTime) }

    $script:PreviousRoot = $env:CIPPRootPath
    $env:CIPPRootPath = $RepoRoot
}

AfterAll { $env:CIPPRootPath = $script:PreviousRoot }

Describe 'Push-CIPPStandardsList cloud support' {
    BeforeEach {
        $script:CIPPCloudFeatureSupport = $null
        Mock Get-CIPPStandards {
            foreach ($Name in 'TeamsGuestAccess', 'AuditLog', 'SharePointMassDeletionAlert') {
                [pscustomobject]@{ Tenant = $TenantFilter; Standard = $Name; Settings = [pscustomobject]@{}; TemplateId = 'tpl-1' }
            }
        }
        Mock Set-CIPPStandardsCompareField {}
        Mock Write-LogMessage {}
    }

    It 'returns every standard for a Commercial tenant, logs nothing and never reads the matrix' {
        Mock Get-CIPPTenantRequestCloud { 'Commercial' }
        Mock Get-CIPPCloudFeatureSupport {}
        $Result = Push-CIPPStandardsList -Item @{ TenantFilter = 'contoso.onmicrosoft.com' } 6>$null

        @($Result.Standard | Sort-Object) | Should -Be @('AuditLog', 'SharePointMassDeletionAlert', 'TeamsGuestAccess')
        Should -Invoke Set-CIPPStandardsCompareField -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly
        Should -Invoke Get-CIPPCloudFeatureSupport -Times 0 -Exactly
    }

    It 'drops unsupported standards for a government tenant with one informational log line' {
        Mock Get-CIPPTenantRequestCloud { 'USGovHigh' }
        $Result = Push-CIPPStandardsList -Item @{ TenantFilter = 'gov.onmicrosoft.us' } 6>$null

        @($Result.Standard) | Should -Be @('AuditLog')
        Should -Invoke Write-LogMessage -Times 1 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Info' -and $message -like '*2 standard(s) not supported for USGovHigh*SharePointMassDeletionAlert, TeamsGuestAccess*' }
        Should -Invoke Set-CIPPStandardsCompareField -Times 1 -Exactly -ParameterFilter {
            @($BulkFields.FieldName | Sort-Object) -join ',' -eq 'standards.SharePointMassDeletionAlert,standards.TeamsGuestAccess' -and
            @($BulkFields | Where-Object { $_.FieldValue -cne 'License Missing: Not supported for USGovHigh tenants.' -or $_.LicenseAvailable -ne $false }).Count -eq 0
        }
    }
}

Describe 'Push-CIPPStandard cloud support' {
    BeforeEach {
        $script:CIPPCloudFeatureSupport = $null
        Mock Test-CIPPRerun { $true }
        Mock Write-LogMessage {}
    }

    It 'goes on to the rerun check for a Commercial tenant' {
        Mock Get-CIPPTenantRequestCloud { 'Commercial' }
        Push-CIPPStandard -Item @{ Tenant = 'contoso.onmicrosoft.com'; Standard = 'TeamsGuestAccess'; TemplateId = 'tpl-1'; QueuedTime = 0 } 6>$null
        Should -Invoke Test-CIPPRerun -Times 1 -Exactly
    }

    It 'returns before the rerun check, without logging, for an unsupported standard on a government tenant' {
        Mock Get-CIPPTenantRequestCloud { 'USGovDoD' }
        Push-CIPPStandard -Item @{ Tenant = 'gov.onmicrosoft.us'; Standard = 'TeamsGuestAccess'; TemplateId = 'tpl-1'; QueuedTime = 0 } 6>$null
        Should -Invoke Test-CIPPRerun -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 0 -Exactly
    }
}
