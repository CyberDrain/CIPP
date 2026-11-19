# Pester tests for Set-CIPPDBCacheIntunePolicies: assignment results are matched back to their policy by id
# (first policy wins on a duplicate id), and device statuses are fetched one $batch (20 policies) at a time.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPDB/Public/DBCache/Set-CIPPDBCacheIntunePolicies.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntunePolicyReportTypeFilter.ps1')
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-CIPPIntunePolicyListDefinitions.ps1' | Select-Object -First 1).FullName

    function Test-CIPPStandardLicense { $true }
    function Get-CIPPIntuneReportRows { param($TenantFilter, $Uri, $Filter, $Select, $OrderBy, $PageSize) , @() }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }
    function Get-CIPPOmaSettingDecryptedValue { param($DeviceConfiguration, $DeviceConfigurationId, $TenantFilter) }
    function Add-CIPPDbItem {
        param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty)
        $script:Written[$Type] = @($Data)
    }
    function New-GraphBulkRequest {
        param($Requests, $tenantid)
        $script:BulkSizes.Add(@($Requests).Count)
        foreach ($Request in @($Requests)) {
            $Value = if ($Request.url -like '*/assignments') {
                @([pscustomobject]@{ id = "$($Request.id)-assignment" })
            } elseif ($Request.url -like '*/deviceStatuses*') {
                @([pscustomobject]@{ id = "$($Request.id)-status" })
            } elseif ($Request.id -eq 'MobileApps') {
                @([pscustomobject]@{ id = 'app-1'; displayName = 'First' }, [pscustomobject]@{ id = 'app-2'; displayName = 'Second' }, [pscustomobject]@{ id = 'app-1'; displayName = 'Duplicate' })
            } elseif ($Request.id -eq 'DeviceConfigurations') {
                @(foreach ($i in 1..45) { [pscustomobject]@{ id = "cfg-$i"; displayName = "Config $i" } })
            } else {
                @()
            }
            [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = $Value } }
        }
    }
}

Describe 'Set-CIPPDBCacheIntunePolicies' {
    BeforeEach {
        $script:Written = @{}
        $script:BulkSizes = [System.Collections.Generic.List[int]]::new()
        Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.com' 3>$null
    }

    It 'attaches each assignment result to the first policy with that id' {
        $Apps = $script:Written['IntuneMobileApps']
        $Apps[0].assignments.id | Should -Be 'app-1-assignment'
        $Apps[1].assignments.id | Should -Be 'app-2-assignment'
        $Apps[2].PSObject.Properties['assignments'] | Should -BeNullOrEmpty
    }

    It 'fetches device statuses 20 policies at a time and writes every policy' {
        ($script:BulkSizes -join ',') | Should -Match '(^|,)20,20,5(,|$)'
        foreach ($i in 1..45) { $script:Written["IntuneDeviceConfigurations_cfg-$i"].id | Should -Be "cfg-$i-status" }
    }
}

Describe 'Set-CIPPDBCacheIntunePolicies settings catalog device reports' {
    BeforeAll {
        $script:CatalogA = '11111111-1111-4111-8111-111111111111'
        $script:CatalogB = '22222222-2222-4222-8222-222222222222'
        $script:CatalogEmpty = '33333333-3333-4333-8333-333333333333'
    }

    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Warnings = [System.Collections.Generic.List[string]]::new()
        Mock Write-LogMessage { if ($sev -eq 'Warning') { $script:Warnings.Add($message) } }
        Mock Add-CIPPDbItem { $script:Writes.Add([pscustomobject]@{ Type = $Type; Data = @($Data); AddCount = $AddCount.IsPresent; ClearOnEmpty = $ClearOnEmpty.IsPresent }) }
        Mock New-GraphBulkRequest {
            foreach ($Request in @($Requests)) {
                $Value = if ($Request.url -like '*/deviceStatuses*') {
                    @([pscustomobject]@{ id = "x_$($Request.id)_dev-1"; deviceDisplayName = 'PC1' })
                } elseif ($Request.id -eq 'ConfigurationPolicies') {
                    @($script:CatalogA, $script:CatalogB, $script:CatalogEmpty | ForEach-Object { [pscustomobject]@{ id = $_; name = "Policy $_" } })
                } elseif ($Request.id -eq 'DeviceConfigurations') {
                    @([pscustomobject]@{ id = 'cfg-1'; displayName = 'Config 1' })
                } else {
                    @()
                }
                [pscustomobject]@{ id = $Request.id; status = 200; body = [pscustomobject]@{ value = $Value } }
            }
        }
        Mock Get-CIPPIntuneReportRows {
            if ($Filter -like "*$script:CatalogB*") { throw 'Report unavailable' }
            if ($Filter -like "*$script:CatalogEmpty*") { return , @() }
            , @(
                [pscustomobject]@{ IntuneDeviceId = 'dev-1'; UserId = 'user-1'; DeviceName = 'PC1'; UPN = 'a@contoso.com'; ReportStatus = 'Succeeded' }
                [pscustomobject]@{ IntuneDeviceId = 'dev-1'; UserId = '00000000-0000-0000-0000-000000000000'; DeviceName = 'PC1'; UPN = ''; ReportStatus = 'Succeeded' }
                [pscustomobject]@{ DeviceName = 'PC2'; UPN = 'b@contoso.com'; ReportStatus = 'Error' }
            )
        }

        Set-CIPPDBCacheIntunePolicies -TenantFilter 'contoso.com' 3>$null
    }

    It 'caches each catalog policy device report with a key per device and user context' {
        $Write = $script:Writes | Where-Object Type -eq "IntuneConfigurationPolicyDevices_$script:CatalogA"
        $Write.AddCount | Should -BeTrue
        $Write.ClearOnEmpty | Should -BeTrue
        $Write.Data.id | Should -Be @('dev-1|PC1|user-1', 'dev-1|PC1|00000000-0000-0000-0000-000000000000', '|PC2|b@contoso.com')
        $Write.Data[0].ReportStatus | Should -Be 'Succeeded'
        Should -Invoke Get-CIPPIntuneReportRows -Times 1 -Exactly -ParameterFilter {
            $Uri -like '*/reports/getConfigurationPolicyDevicesReport' -and $Filter -like "*(PolicyBaseTypeName eq 'DeviceManagementConfigurationPolicy')*" -and $Filter -like "*(PolicyId eq '$script:CatalogA')"
        }
        Should -Invoke Get-CIPPIntuneReportRows -Times 3 -Exactly
    }

    It 'records an empty report so it reads as no devices rather than no data' {
        $Write = $script:Writes | Where-Object Type -eq "IntuneConfigurationPolicyDevices_$script:CatalogEmpty"
        $Write | Should -HaveCount 1
        $Write.Data | Should -HaveCount 0
        $Write.AddCount | Should -BeTrue
        $Write.ClearOnEmpty | Should -BeTrue
    }

    It 'turns a failed report into a warning and keeps the previous cache' {
        $script:Writes.Type | Should -Not -Contain "IntuneConfigurationPolicyDevices_$script:CatalogB"
        $script:Warnings | Where-Object { $_ -like "*device report for ConfigurationPolicies policy $script:CatalogB*Report unavailable*" } | Should -Not -BeNullOrEmpty
        $script:Writes.Type | Should -Contain "IntuneConfigurationPolicyDevices_$script:CatalogA"
    }

    It 'leaves the existing cache types and their rows unchanged' {
        $Catalog = $script:Writes | Where-Object Type -eq 'IntuneConfigurationPolicies'
        @($Catalog.Data[0].PSObject.Properties.Name) | Should -Be @('id', 'name')
        $Statuses = $script:Writes | Where-Object Type -eq 'IntuneDeviceConfigurations_cfg-1'
        $Statuses.Data.id | Should -Be 'x_cfg-1_dev-1'
        $Statuses.AddCount | Should -BeFalse
        $NewTypes = @($script:Writes.Type | Where-Object { $_ -like 'IntuneConfigurationPolicyDevices*' })
        $NewTypes | Should -HaveCount 2
        $script:Writes.Type | Where-Object { $_ -like 'IntuneDeviceCompliancePolicies_*' } | Should -BeNullOrEmpty
    }
}
