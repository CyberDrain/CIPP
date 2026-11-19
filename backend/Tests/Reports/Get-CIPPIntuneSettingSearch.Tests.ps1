BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function Get-CIPPIntuneDefinitionIndex {}
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) $Exception }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Test-CIPPSingleTenantFilter.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntunePolicyListDefinitions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPIntunePolicyListItem.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-CIPPIntunePolicySetting.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPIntuneSettingSearch.ps1')

    function New-DbItem([string]$Tenant, [string]$Type, [hashtable]$Data) {
        [PSCustomObject]@{
            PartitionKey = $Tenant
            RowKey       = "$Type-$($Data.id)"
            Data         = $Data | ConvertTo-Json -Depth 20 -Compress
        }
    }

    function New-OmaPolicy([string]$Id, [string]$Name, [string[]]$SettingNames) {
        @{
            '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
            id            = $Id
            displayName   = $Name
            omaSettings   = @(foreach ($SettingName in $SettingNames) { @{ '@odata.type' = '#microsoft.graph.omaSettingInteger'; displayName = $SettingName; omaUri = "./Vendor/$SettingName"; value = 1 } })
        }
    }

    function New-CatalogPolicy([string]$Id, [string]$Name, [string]$Option) {
        @{
            id       = $Id
            name     = $Name
            settings = @(
                @{
                    id              = '0'
                    settingInstance = @{
                        '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                        settingDefinitionId = 'device_vendor_msft_defender_allowrealtimemonitoring'
                        choiceSettingValue  = @{ value = $Option; children = @() }
                    }
                }
            )
        }
    }
}

Describe 'Get-CIPPIntuneSettingSearch' {
    BeforeEach {
        $script:TenantA = 'contoso.onmicrosoft.com'
        $script:TenantB = 'fabrikam.onmicrosoft.com'
        $script:RowsByType = @{
            IntuneConfigurationPolicies     = @(
                New-DbItem $script:TenantA 'IntuneConfigurationPolicies' (New-CatalogPolicy 'cat-a' 'Defender A' 'device_vendor_msft_defender_allowrealtimemonitoring_1')
                New-DbItem $script:TenantB 'IntuneConfigurationPolicies' (New-CatalogPolicy 'cat-b' 'Defender B' 'device_vendor_msft_defender_allowrealtimemonitoring_0')
                New-DbItem 'removed.onmicrosoft.com' 'IntuneConfigurationPolicies' (New-CatalogPolicy 'cat-x' 'Stale' 'device_vendor_msft_defender_allowrealtimemonitoring_1')
                [PSCustomObject]@{ PartitionKey = $script:TenantA; RowKey = 'IntuneConfigurationPolicies-Count'; Data = '{"Count":2}' }
            )
            IntuneDeviceConfigurations      = @(
                New-DbItem $script:TenantA 'IntuneDeviceConfigurations' @{
                    '@odata.type'               = '#microsoft.graph.windows10GeneralConfiguration'
                    'assignments@odata.context' = "https://graph.microsoft.com/beta/`$metadata#deviceManagement/deviceConfigurations('x')/microsoft.graph.windows10GeneralConfiguration/assignments"
                    id                          = 'gen-a'
                    displayName                 = 'Windows A'
                    passwordMinimumLength       = 12
                    defenderRequireRealTimeMonitoring = $true
                    cortanaBlocked              = $false
                    lockScreenBlockCortana      = $false
                    printerBlockAddition        = $false
                }
                New-DbItem $script:TenantA 'IntuneDeviceConfigurations' @{
                    '@odata.type' = '#microsoft.graph.windows10CustomConfiguration'
                    id            = 'oma-a'
                    displayName   = 'Custom A'
                    omaSettings   = @(@{ displayName = 'Realtime OMA'; omaUri = './Vendor/MSFT/Defender/RealTime'; value = 1 })
                }
            )
            IntuneGroupPolicyConfigurations = @(
                New-DbItem $script:TenantA 'IntuneGroupPolicyConfigurations' @{ id = 'adm-a'; displayName = 'Realtime admx'; realtimeProperty = 'x' }
            )
            IntuneIntents                   = @(
                New-DbItem $script:TenantA 'IntuneIntents' @{ id = 'int-a'; displayName = 'Realtime intent'; realtimeProperty = 'x' }
            )
        }

        $Options = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Options['device_vendor_msft_defender_allowrealtimemonitoring_0'] = 'Not allowed'
        $Options['device_vendor_msft_defender_allowrealtimemonitoring_1'] = 'Allowed'
        $script:Index = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $script:Index['device_vendor_msft_defender_allowrealtimemonitoring'] = @{ displayName = 'Allow Realtime Monitoring'; options = $Options }

        Mock Write-LogMessage {}
        Mock Get-CIPPIntuneDefinitionIndex { $script:Index }
        Mock Get-CIPPDbItem {
            @($script:RowsByType[$Type] | Where-Object { $TenantFilter -eq 'allTenants' -or $_.PartitionKey -eq $TenantFilter })
        }
    }

    It 'matches the setting name case-insensitively across setting kinds' {
        $Result = @(Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'REALTIME')

        $Result.SettingId | Should -Be @(
            'device_vendor_msft_defender_allowrealtimemonitoring'
            'windows10GeneralConfiguration/defenderRequireRealTimeMonitoring'
            './Vendor/MSFT/Defender/RealTime'
        )
        $Catalog = $Result[0]
        $Catalog.SettingName | Should -Be 'Allow Realtime Monitoring'
        $Catalog.Category | Should -Be 'Device Configuration'
        $Catalog.PolicyCount | Should -Be 1
        $Catalog.PolicyTypes | Should -Be 'Device Configuration'
        $Catalog.PSObject.Properties.Name | Should -Not -Contain 'TenantCount'
        $Catalog.Policies[0].Tenant | Should -Be $script:TenantA
        $Catalog.Policies[0].PolicyId | Should -Be 'cat-a'
        $Catalog.Policies[0].PolicyName | Should -Be 'Defender A'
        $Catalog.Policies[0].PolicyTypeName | Should -Be 'Device Configuration'
        $Catalog.Policies[0].URLName | Should -Be 'ConfigurationPolicies'
        $Catalog.Policies[0].Value | Should -Be 'Allowed'

        $Property = $Result[1]
        $Property.SettingName | Should -Be 'Defender require real time monitoring'
        $Property.Category | Should -Be 'Windows Configuration'
        $Property.Policies[0].URLName | Should -Be 'DeviceConfigurations'
        $Property.Policies[0].Value | Should -Be 'true'

        $Result[2].SettingName | Should -Be 'Realtime OMA'
        $Result[2].Category | Should -Be 'windows10CustomConfiguration'
    }

    It 'uses the policy type label from the assignment context as the category' {
        $script:RowsByType['IntuneDeviceConfigurations'] = @(
            New-DbItem $script:TenantA 'IntuneDeviceConfigurations' @{
                '@odata.type'               = '#microsoft.graph.windows10CustomConfiguration'
                'assignments@odata.context' = "https://graph.microsoft.com/beta/`$metadata#deviceManagement/deviceConfigurations('x')/microsoft.graph.windows10CustomConfiguration/assignments"
                id                          = 'oma-a'
                displayName                 = 'Custom A'
                omaSettings                 = @(@{ displayName = 'Realtime OMA'; omaUri = './Vendor/MSFT/Defender/RealTime'; value = 1 })
            }
        )

        $Result = @(Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'Realtime OMA')

        $Result.Category | Should -Be 'Custom'
        $Result.Policies.PolicyTypeName | Should -Be 'Custom'
    }

    It 'matches the setting id' {
        $Result = @(Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'passwordMinimum')
        $Result.SettingId | Should -Be 'windows10GeneralConfiguration/passwordMinimumLength'
        $Result.Policies.Value | Should -Be '12'
    }

    It 'does not match booleans the policy leaves unset' {
        Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'cortana' | Should -BeNullOrEmpty
        Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'printer' | Should -BeNullOrEmpty
    }

    It 'skips families whose settings are not cached' {
        Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'realtimeProperty' | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPDbItem -Times 0 -Exactly -ParameterFilter { $Type -in @('IntuneGroupPolicyConfigurations', 'IntuneIntents') }
    }

    It 'groups one setting across the policies of the tenant only' {
        $script:RowsByType['IntuneConfigurationPolicies'] += New-DbItem $script:TenantA 'IntuneConfigurationPolicies' (New-CatalogPolicy 'cat-a2' 'Another Defender' 'device_vendor_msft_defender_allowrealtimemonitoring_0')

        $Result = @(Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'allow realtime')

        $Result | Should -HaveCount 1
        $Result[0].PolicyCount | Should -Be 2
        $Result[0].Policies.PolicyName | Should -Be @('Another Defender', 'Defender A')
        $Result[0].Policies.Value | Should -Be @('Not allowed', 'Allowed')
        $Result[0].Policies.Tenant | Sort-Object -Unique | Should -Be $script:TenantA
        Should -Invoke Get-CIPPDbItem -Times 0 -Exactly -ParameterFilter { $TenantFilter -ne $script:TenantA }
    }

    It 'lists the distinct policy types of a setting sorted' {
        $EndpointProtection = "https://graph.microsoft.com/beta/`$metadata#deviceManagement/deviceConfigurations('x')/microsoft.graph.windows10EndpointProtectionConfiguration/assignments"
        $script:RowsByType['IntuneConfigurationPolicies'] = @(
            New-DbItem $script:TenantA 'IntuneConfigurationPolicies' ((New-CatalogPolicy 'cat-a' 'Defender A' 'device_vendor_msft_defender_allowrealtimemonitoring_1') + @{ 'assignments@odata.context' = $EndpointProtection })
            New-DbItem $script:TenantA 'IntuneConfigurationPolicies' (New-CatalogPolicy 'cat-b' 'Defender B' 'device_vendor_msft_defender_allowrealtimemonitoring_0')
            New-DbItem $script:TenantA 'IntuneConfigurationPolicies' ((New-CatalogPolicy 'cat-c' 'Defender C' 'device_vendor_msft_defender_allowrealtimemonitoring_1') + @{ 'assignments@odata.context' = $EndpointProtection })
        )

        $Result = @(Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'allow realtime')

        $Result | Should -HaveCount 1
        $Result[0].PolicyCount | Should -Be 3
        $Result[0].PolicyTypes | Should -Be 'Device Configuration, Endpoint Protection'
    }

    It 'refuses <Name>' -ForEach @(
        @{ Name = 'AllTenants'; TenantFilter = 'AllTenants' }
        @{ Name = 'a tenant group'; TenantFilter = 'group:0f6c1e3a-4c8e-4d55-9a0b-2f4e6d7c8b9a' }
    ) {
        { Get-CIPPIntuneSettingSearch -TenantFilter $TenantFilter -Search 'allow realtime' } | Should -Throw
        Should -Invoke Get-CIPPDbItem -Times 0 -Exactly
    }

    Context 'with MaxResults' {
        BeforeEach {
            $script:RowsByType['IntuneConfigurationPolicies'] = @()
            $script:RowsByType['IntuneDeviceConfigurations'] = @(
                New-DbItem $script:TenantA 'IntuneDeviceConfigurations' (New-OmaPolicy 'oma-1' 'First' @('Capped Zulu', 'Capped Yankee', 'Capped Xray'))
                New-DbItem $script:TenantA 'IntuneDeviceConfigurations' (New-OmaPolicy 'oma-2' 'Second' @('Capped Alpha', 'Capped Zulu', 'Capped Bravo'))
                New-DbItem $script:TenantA 'IntuneDeviceConfigurations' (New-OmaPolicy 'oma-3' 'Third' @('Capped Yankee', 'Capped Charlie'))
            )
        }

        It 'keeps at most MaxResults + 1 settings, the first found, sorted' {
            $Result = @(Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'Capped' -MaxResults 2)

            $Result.SettingName | Should -Be @('Capped Xray', 'Capped Yankee', 'Capped Zulu')
        }

        It 'still adds later policies to the settings it kept' {
            $Result = @(Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'Capped' -MaxResults 2)

            ($Result | Where-Object SettingName -eq 'Capped Zulu').Policies.PolicyId | Should -Be @('oma-1', 'oma-2')
            ($Result | Where-Object SettingName -eq 'Capped Yankee').Policies.PolicyId | Should -Be @('oma-1', 'oma-3')
            ($Result | Where-Object SettingName -eq 'Capped Yankee').PolicyCount | Should -Be 2
        }

        It 'returns every match sorted when fewer than MaxResults + 1 match' {
            $Result = @(Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'Capped' -MaxResults 10)

            $Result.SettingName | Should -Be @('Capped Alpha', 'Capped Bravo', 'Capped Charlie', 'Capped Xray', 'Capped Yankee', 'Capped Zulu')
        }
    }

    It 'lists a policy once when it sets the same setting several times' {
        $Policy = New-CatalogPolicy 'cat-multi' 'Multi' 'device_vendor_msft_defender_allowrealtimemonitoring_1'
        $Policy.settings += @{
            id              = '1'
            settingInstance = @{
                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                settingDefinitionId = 'device_vendor_msft_defender_allowrealtimemonitoring'
                choiceSettingValue  = @{ value = 'device_vendor_msft_defender_allowrealtimemonitoring_0'; children = @() }
            }
        }
        $script:RowsByType['IntuneConfigurationPolicies'] = @(New-DbItem $script:TenantA 'IntuneConfigurationPolicies' $Policy)

        $Result = @(Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'Allow Realtime')

        $Result.PolicyCount | Should -Be 1
        $Result.Policies.Value | Should -Be 'Allowed, Not allowed'
    }

    It 'lists each value once per policy in the order first seen' {
        $Policy = New-CatalogPolicy 'cat-multi' 'Multi' 'device_vendor_msft_defender_allowrealtimemonitoring_1'
        foreach ($Option in @('device_vendor_msft_defender_allowrealtimemonitoring_0', 'device_vendor_msft_defender_allowrealtimemonitoring_1')) {
            $Policy.settings += @{
                id              = "$($Policy.settings.Count)"
                settingInstance = @{
                    '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                    settingDefinitionId = 'device_vendor_msft_defender_allowrealtimemonitoring'
                    choiceSettingValue  = @{ value = $Option; children = @() }
                }
            }
        }
        $script:RowsByType['IntuneConfigurationPolicies'] = @(New-DbItem $script:TenantA 'IntuneConfigurationPolicies' $Policy)

        $Result = @(Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'Allow Realtime')

        $Result.Policies.Value | Should -Be 'Allowed, Not allowed'
    }

    It 'returns nothing when no setting matches' {
        Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'nothing-matches-this' | Should -BeNullOrEmpty
    }

    It 'skips cached rows that cannot be parsed' {
        $script:RowsByType['IntuneConfigurationPolicies'] += [PSCustomObject]@{ PartitionKey = $script:TenantA; RowKey = 'bad'; Data = '{not json' }

        @(Get-CIPPIntuneSettingSearch -TenantFilter $script:TenantA -Search 'Allow Realtime') | Should -HaveCount 1
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' }
    }
}
