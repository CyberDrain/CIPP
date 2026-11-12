# A classic standard a government tenant's cloud does not support (redanthrax/CIPP#4) is written by
# Push-CIPPStandardsList with the 'License Missing:' marker, so Get-CIPPTenantAlignment leaves it out of the
# alignment score exactly as it does a missing licence. Commercial rows are graded as before.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Functions/Get-CIPPTenantAlignment.ps1')

    function Get-CippTable { param($tablename) @{ Table = $tablename } }
    function Get-TenantGroups { @() }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPAzDataTableEntity { param($Table, $Filter) }

    $script:Template = [pscustomobject]@{
        RowKey = 'tpl-1'; GUID = 'tpl-1'
        JSON   = ([ordered]@{
                templateName = 'Gov test'
                type         = 'classic'
                tenantFilter = @(@{ value = 'AllTenants'; type = 'Tenant' })
                standards    = @{
                    AuditLog         = @{ action = @(@{ value = 'report' }) }
                    TeamsGuestAccess = @{ action = @(@{ value = 'report' }) }
                }
            } | ConvertTo-Json -Depth 10)
    }

    function script:Invoke-Alignment {
        param([string]$Tenant, $UnsupportedValue, $LicenseAvailable = $false)
        $script:Rows = @(
            [pscustomobject]@{ PartitionKey = $Tenant; RowKey = 'standards.AuditLog'; Value = $true; LicenseAvailable = $true; TimeStamp = [datetime]::UtcNow }
            [pscustomobject]@{ PartitionKey = $Tenant; RowKey = 'standards.TeamsGuestAccess'; Value = $UnsupportedValue; LicenseAvailable = $LicenseAvailable; TimeStamp = [datetime]::UtcNow }
        )
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -eq "PartitionKey eq 'StandardsTemplateV2'") { return $script:Template }
            if ($Filter -like "PartitionKey eq '*.*'") { return $script:Rows }
            @()
        }
        Get-CIPPTenantAlignment -TenantFilter $Tenant
    }
}

Describe 'Get-CIPPTenantAlignment cloud-unsupported standards' {
    It 'leaves a government cloud-unsupported standard out of the score, like a missing licence' {
        $Result = script:Invoke-Alignment -Tenant 'gov.onmicrosoft.us' -UnsupportedValue 'License Missing: Not supported for USGovHigh tenants.'
        $Result.LicenseMissingStandards | Should -Be 1
        $Result.NonCompliantStandards | Should -Be 0
        $Result.CombinedScore | Should -Be 100
        ($Result.ComparisonDetails | Where-Object StandardName -EQ 'standards.TeamsGuestAccess').ComplianceStatus | Should -Be 'License Missing'
    }

    It 'grades the same row exactly as a License Missing row' {
        $Gov = script:Invoke-Alignment -Tenant 'gov.onmicrosoft.us' -UnsupportedValue 'License Missing: Not supported for USGovHigh tenants.'
        $Lic = script:Invoke-Alignment -Tenant 'gov.onmicrosoft.us' -UnsupportedValue 'License Missing: This tenant is not licensed for the following capabilities: X'
        foreach ($Prop in 'AlignmentScore', 'LicenseMissingPercentage', 'CombinedScore', 'CompliantStandards', 'NonCompliantStandards', 'LicenseMissingStandards') {
            $Gov.$Prop | Should -Be $Lic.$Prop
        }
    }

    It 'still grades an ordinary non-compliant commercial value as Non-Compliant' {
        $Result = script:Invoke-Alignment -Tenant 'contoso.onmicrosoft.com' -UnsupportedValue $false -LicenseAvailable $true
        $Result.NonCompliantStandards | Should -Be 1
        $Result.LicenseMissingStandards | Should -Be 0
        $Result.AlignmentScore | Should -Be 50
        $Result.CombinedScore | Should -Be 50
    }
}
