BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CippTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPODataFilterValue.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntunePolicyListDefinitions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Add-CIPPIntuneSettingDeviceCount.ps1')

    $script:TenantA = 'contoso.onmicrosoft.com'
    $script:TenantB = 'fabrikam.onmicrosoft.com'
    $script:Catalog = '11111111-1111-4111-8111-111111111111'
    $script:Compliance = '22222222-2222-4222-8222-222222222222'
    $script:Config = '33333333-3333-4333-8333-333333333333'
    $script:EmptyCatalog = '44444444-4444-4444-8444-444444444444'
    $script:Feature = '55555555-5555-4555-8555-555555555555'

    function New-Policy([string]$Tenant, [string]$URLName, [string]$PolicyId) {
        [PSCustomObject]@{ Tenant = $Tenant; PolicyId = $PolicyId; PolicyName = $PolicyId; URLName = $URLName; DeviceCount = $null }
    }

    function New-Result([object[]]$Policies) {
        [PSCustomObject]@{ SettingId = 's'; SettingName = 'S'; DeviceCount = $null; Policies = @($Policies) }
    }

    function New-Row([string]$Tenant, [string]$RowKey) {
        [PSCustomObject]@{ PartitionKey = $Tenant; RowKey = $RowKey }
    }

    function Select-TableRow([string]$Filter) {
        if ($Filter -notmatch "^PartitionKey eq '(.+)' and RowKey ge '(.+)' and RowKey lt '(.+)'$") { throw "Unexpected filter $Filter" }
        $Partition, $From, $To = $Matches[1], $Matches[2], $Matches[3]
        $script:Table | Where-Object {
            $_.PartitionKey -eq $Partition -and [string]::CompareOrdinal($_.RowKey, $From) -ge 0 -and [string]::CompareOrdinal($_.RowKey, $To) -lt 0
        }
    }
}

Describe 'Add-CIPPIntuneSettingDeviceCount' {
    BeforeEach {
        $script:Table = @(
            New-Row $script:TenantA "IntuneConfigurationPolicyDevices_$script:Catalog-dev-1|PC1|user-1"
            New-Row $script:TenantA "IntuneConfigurationPolicyDevices_$script:Catalog-dev-1|PC1|00000000-0000-0000-0000-000000000000"
            New-Row $script:TenantA "IntuneConfigurationPolicyDevices_$script:Catalog-dev-2|PC2|user-2"
            New-Row $script:TenantA "IntuneConfigurationPolicyDevices_$script:Catalog-Count"
            New-Row $script:TenantA "IntuneConfigurationPolicyDevices_$script:EmptyCatalog-Count"
            New-Row $script:TenantA "IntuneDeviceCompliancePolicies_$script:Compliance-x_$($script:Compliance)_dev-2"
            New-Row $script:TenantA "IntuneDeviceCompliancePolicies_$script:Compliance-x_$($script:Compliance)_dev-3"
            New-Row $script:TenantA "IntuneDeviceCompliancePolicies-$script:Compliance"
            New-Row $script:TenantB "IntuneConfigurationPolicyDevices_$script:Catalog-dev-1|PC1|user-1"
            New-Row $script:TenantB "IntuneConfigurationPolicyDevices_$script:Catalog-Count"
        )
        Mock Get-CIPPAzDataTableEntity { Select-TableRow $Filter }
        Mock Get-Tenants { [PSCustomObject]@{ defaultDomainName = $script:TenantA } }
    }

    It 'counts distinct devices across the policies of a setting' {
        $Result = New-Result @(
            New-Policy $script:TenantA 'ConfigurationPolicies' $script:Catalog
            New-Policy $script:TenantA 'deviceCompliancePolicies' $script:Compliance
        )

        Add-CIPPIntuneSettingDeviceCount -TenantFilter $script:TenantA -Results @($Result)

        $Result.Policies[0].DeviceCount | Should -Be 2
        $Result.Policies[1].DeviceCount | Should -Be 2
        $Result.DeviceCount | Should -Be 3
    }

    It 'counts a device keyed by name in one row and by id in another once' {
        $Other = '66666666-6666-4666-8666-666666666666'
        $script:Table += @(
            New-Row $script:TenantA "IntuneConfigurationPolicyDevices_$script:Catalog-|pc1|user-9"
            New-Row $script:TenantA "IntuneConfigurationPolicyDevices_$Other-|PC1|user-1"
            New-Row $script:TenantA "IntuneConfigurationPolicyDevices_$Other-|PC|9|user-1"
            New-Row $script:TenantA "IntuneConfigurationPolicyDevices_$Other-Count"
        )
        $Result = New-Result @(
            New-Policy $script:TenantA 'ConfigurationPolicies' $script:Catalog
            New-Policy $script:TenantA 'ConfigurationPolicies' $Other
        )

        Add-CIPPIntuneSettingDeviceCount -TenantFilter $script:TenantA -Results @($Result)

        $Result.Policies[0].DeviceCount | Should -Be 2
        $Result.Policies[1].DeviceCount | Should -Be 2
        $Result.DeviceCount | Should -Be 3
    }

    It 'is null when no policy has cached device data' {
        $Result = New-Result @(
            New-Policy $script:TenantA 'WindowsFeatureUpdateProfiles' $script:Feature
            New-Policy $script:TenantA 'DeviceConfigurations' $script:Config
        )

        Add-CIPPIntuneSettingDeviceCount -TenantFilter $script:TenantA -Results @($Result)

        $Result.DeviceCount | Should -BeNullOrEmpty
        @($Result.Policies | Where-Object { $null -ne $_.DeviceCount }) | Should -HaveCount 0
        $Result.PSObject.Properties['DeviceCount'] | Should -Not -BeNullOrEmpty
    }

    It 'is 0 when a policy has a cached report without devices' {
        $Result = New-Result @(
            New-Policy $script:TenantA 'ConfigurationPolicies' $script:EmptyCatalog
            New-Policy $script:TenantA 'WindowsFeatureUpdateProfiles' $script:Feature
        )

        Add-CIPPIntuneSettingDeviceCount -TenantFilter $script:TenantA -Results @($Result)

        $Result.DeviceCount | Should -Be 0
        $Result.DeviceCount | Should -BeOfType [int]
        $Result.Policies[0].DeviceCount | Should -Be 0
        $Result.Policies[1].DeviceCount | Should -BeNullOrEmpty
    }

    It 'resolves a single tenant to its reporting partition' {
        Mock Get-Tenants { [PSCustomObject]@{ defaultDomainName = $script:TenantA } } -ParameterFilter { $TenantFilter -eq 'contoso.com' }
        $Result = New-Result @(New-Policy 'contoso.com' 'ConfigurationPolicies' $script:Catalog)

        Add-CIPPIntuneSettingDeviceCount -TenantFilter 'contoso.com' -Results @($Result)

        $Result.DeviceCount | Should -Be 2
    }

    It 'reads only the policies in the results, one range per policy' {
        $Results = @(
            New-Result @(New-Policy $script:TenantA 'ConfigurationPolicies' $script:Catalog)
            New-Result @(New-Policy $script:TenantA 'deviceCompliancePolicies' $script:Compliance)
            New-Result @(New-Policy $script:TenantA 'WindowsFeatureUpdateProfiles' $script:Feature)
        )

        Add-CIPPIntuneSettingDeviceCount -TenantFilter $script:TenantA -Results $Results

        Should -Invoke Get-CIPPAzDataTableEntity -Times 2 -Exactly
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Filter -eq "PartitionKey eq '$script:TenantA' and RowKey ge 'IntuneConfigurationPolicyDevices_$script:Catalog-' and RowKey lt 'IntuneConfigurationPolicyDevices_$script:Catalog.'" -and
            (@($Property) -join ',') -eq 'PartitionKey,RowKey'
        }
    }

    It 'reads a whole family once when many of its policies are in the results' {
        $Others = 1..6 | ForEach-Object { '{0:d8}-0000-4000-8000-000000000000' -f $_ }
        $Policies = @($Others | ForEach-Object { New-Policy $script:TenantA 'ConfigurationPolicies' $_ }) + @(New-Policy $script:TenantA 'ConfigurationPolicies' $script:Catalog)
        $Result = New-Result $Policies

        Add-CIPPIntuneSettingDeviceCount -TenantFilter $script:TenantA -Results @($Result)

        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
            $Filter -eq "PartitionKey eq '$script:TenantA' and RowKey ge 'IntuneConfigurationPolicyDevices_' and RowKey lt 'IntuneConfigurationPolicyDevices``'"
        }
        $Result.DeviceCount | Should -Be 2
        @($Result.Policies | Where-Object { $null -ne $_.DeviceCount }) | Should -HaveCount 1
    }

    It 'does nothing for an empty result set' {
        Add-CIPPIntuneSettingDeviceCount -TenantFilter $script:TenantA -Results @()

        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
    }
}
