# policies/roleManagementPolicyAssignments rejects any request without a scopeId/scopeType filter
# with 400 "The provider is missing.", so PIMRoleSettings was never written for a P2 tenant and the
# collector logged a Warning every night. This holds the filter in place.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }

    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCachePIMSettings.ps1')
}

Describe 'Set-CIPPDBCachePIMSettings' {
    BeforeEach {
        Mock Test-CIPPStandardLicense { $true }
        Mock Write-LogMessage {}
        Mock Add-CIPPDbItem {}
        Mock New-GraphGetRequest { @([pscustomobject]@{ id = 'DirectoryRole_1'; policyId = 'DirectoryRole_1' }) }
    }

    It 'scopes the role management policy assignment read to directory roles' {
        Set-CIPPDBCachePIMSettings -TenantFilter 'contoso.onmicrosoft.com'

        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter {
            $uri -like '*/policies/roleManagementPolicyAssignments?*' -and
            $uri -like "*`$filter=scopeId eq '/' and scopeType eq 'DirectoryRole'*"
        }
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $Type -eq 'PIMRoleSettings' -and @($Data).Count -eq 1 }
    }
}
