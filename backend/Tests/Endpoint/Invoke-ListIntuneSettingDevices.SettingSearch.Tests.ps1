BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CIPPDbItem { param($TenantFilter, $Type) }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPIntuneDefinitionIndex {}
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    function Get-NormalizedError { param($Message) $Message }
    function New-GraphGetRequest { param($uri, $tenantid) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body) }
    function New-GraphBulkRequest { param($Requests, $tenantid) }

    foreach ($Name in 'Test-CIPPSingleTenantFilter', 'Get-CIPPIntunePolicyListDefinitions', 'ConvertTo-CIPPIntunePolicyListItem', 'ConvertTo-CIPPIntunePolicySetting', 'Get-CIPPIntuneSettingSearch', 'Get-CIPPIntuneReportRows', 'Get-CIPPIntuneDeploymentStatus', 'Get-CIPPIntunePolicyReportTypeFilter') {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$Name.ps1")
    }
    $EndpointRoot = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Endpoint/MEM'
    foreach ($Name in 'Invoke-ListIntuneSettingSearch', 'Invoke-ListIntuneSettingDevices') {
        . ([ScriptBlock]::Create("using namespace System.Net`n" + (Get-Content -LiteralPath (Join-Path $EndpointRoot "$Name.ps1") -Raw)))
    }

    $script:TenantA = 'contoso.onmicrosoft.com'
    $script:TenantB = 'fabrikam.onmicrosoft.com'
    $script:CatalogA = '0d2b7a51-6c1e-4f6a-9d39-1f0a2d0c0a01'
    $script:CatalogB = '0d2b7a51-6c1e-4f6a-9d39-1f0a2d0c0b02'
    $script:ConfigA = '0d2b7a51-6c1e-4f6a-9d39-1f0a2d0c0a03'
    $script:FeatureA = '0d2b7a51-6c1e-4f6a-9d39-1f0a2d0c0a04'
    $script:AppProtectionA = 'T_0d2b7a51-6c1e-4f6a-9d39-1f0a2d0c0a05'

    function New-DbItem([string]$Tenant, [string]$Type, $Data) {
        [PSCustomObject]@{ PartitionKey = $Tenant; RowKey = "$Type-$($Data.id)"; Data = $Data | ConvertTo-Json -Depth 20 -Compress }
    }

    function New-CatalogPolicy([string]$Id, [string]$Name) {
        @{
            id       = $Id
            name     = $Name
            settings = @(@{
                    id              = '0'
                    settingInstance = @{
                        '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                        settingDefinitionId = 'device_vendor_msft_defender_allowrealtimemonitoring'
                        choiceSettingValue  = @{ value = 'device_vendor_msft_defender_allowrealtimemonitoring_1'; children = @() }
                    }
                })
        }
    }

    function Invoke-Endpoint([string]$Name, [hashtable]$Query) {
        $Response = & $Name -Request ([PSCustomObject]@{ Params = @{ CIPPEndpoint = $Name -replace '^Invoke-' }; Headers = @{}; Query = [PSCustomObject]$Query }) -TriggerMetadata $null
        [PSCustomObject]@{ StatusCode = [int]$Response.StatusCode; Body = $Response.Body | ConvertTo-Json -Depth 20 -Compress | ConvertFrom-Json }
    }

    function Get-DeviceRequests($Policies) {
        foreach ($Group in @($Policies | Group-Object Tenant)) {
            @{ tenantFilter = $Group.Name; Policies = (@($Group.Group | ForEach-Object { "$($_.URLName):$($_.PolicyId)" }) -join ',') }
        }
    }
}

Describe 'Setting search results feeding ListIntuneSettingDevices' {
    BeforeEach {
        $script:Rows = @{
            IntuneConfigurationPolicies        = @(
                New-DbItem $script:TenantA 'IntuneConfigurationPolicies' (New-CatalogPolicy $script:CatalogA 'Defender A')
                New-DbItem $script:TenantB 'IntuneConfigurationPolicies' (New-CatalogPolicy $script:CatalogB 'Defender B')
            )
            IntuneDeviceConfigurations         = @(
                New-DbItem $script:TenantA 'IntuneDeviceConfigurations' @{
                    '@odata.type'                     = '#microsoft.graph.windows10GeneralConfiguration'
                    id                                = $script:ConfigA
                    displayName                       = 'Restrictions A'
                    defenderRequireRealTimeMonitoring = $true
                }
            )
            "IntuneDeviceConfigurations_$script:ConfigA" = @(
                [PSCustomObject]@{ PartitionKey = $script:TenantA; RowKey = 's1'; Data = (@{ deviceDisplayName = 'PC-CACHED'; userPrincipalName = "a@$script:TenantA"; status = 'compliant' } | ConvertTo-Json -Compress) }
            )
            IntuneWindowsFeatureUpdateProfiles = @(
                New-DbItem $script:TenantA 'IntuneWindowsFeatureUpdateProfiles' @{ id = $script:FeatureA; displayName = 'Feature A'; featureUpdateVersion = 'Windows 11, version 24H2' }
            )
            IntuneAppProtectionPolicies        = @(
                New-DbItem $script:TenantA 'IntuneAppProtectionPolicies' @{ '@odata.type' = '#microsoft.graph.iosManagedAppProtection'; id = $script:AppProtectionA; displayName = 'iOS A'; pinRequired = $true }
            )
        }

        $Index = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $Index['device_vendor_msft_defender_allowrealtimemonitoring'] = @{ displayName = 'Allow Realtime Monitoring'; options = $null; categoryName = 'Defender' }
        $script:Index = $Index

        Mock Write-LogMessage {}
        Mock Get-CIPPIntuneDefinitionIndex { $script:Index }
        Mock Get-Tenants { @([PSCustomObject]@{ defaultDomainName = $script:TenantA }, [PSCustomObject]@{ defaultDomainName = $script:TenantB }) }
        Mock Get-CIPPDbItem { @($script:Rows[$Type] | Where-Object { $TenantFilter -eq 'allTenants' -or $_.PartitionKey -eq $TenantFilter }) }
        Mock New-GraphGetRequest {}
        Mock New-GraphPOSTRequest {
            $PolicyId = [regex]::Match((($body | ConvertFrom-Json).filter), "PolicyId eq '([^']+)'").Groups[1].Value
            [PSCustomObject]@{
                TotalRowCount = 1
                Schema        = @('DeviceName', 'UPN', 'ReportStatus_loc' | ForEach-Object { [PSCustomObject]@{ Column = $_ } })
                Values        = @(, @("PC-$PolicyId", "u@$tenantid", 'Succeeded'))
            }
        }
    }

    It 'accepts every policy a tenant search returns' {
        $Search = Invoke-Endpoint 'Invoke-ListIntuneSettingSearch' @{ TenantFilter = $script:TenantA; search = 'realtime' }
        $Search.StatusCode | Should -Be 200
        $Policies = @($Search.Body.Results.Policies)
        $Policies.URLName | Sort-Object -Unique | Should -Be @('ConfigurationPolicies', 'DeviceConfigurations')
        $Policies.Tenant | Sort-Object -Unique | Should -Be $script:TenantA

        $Devices = foreach ($Request in Get-DeviceRequests $Policies) {
            $Response = Invoke-Endpoint 'Invoke-ListIntuneSettingDevices' $Request
            $Response.StatusCode | Should -Be 200
            @($Response.Body.Metadata.Warnings) | Should -HaveCount 0
            $Response.Body.Results | Add-Member -NotePropertyName Tenant -NotePropertyValue $Request.tenantFilter -PassThru
        }

        @($Devices | ForEach-Object { "$($_.Tenant)|$($_.PolicyId)|$($_.DeviceName)|$($_.Source)" }) | Sort-Object | Should -Be @(
            "$script:TenantA|$script:CatalogA|PC-$script:CatalogA|Live"
            "$script:TenantA|$script:ConfigA|PC-CACHED|Cache"
        )
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly -ParameterFilter { $tenantid -eq $script:TenantB }
    }

    It 'accepts families without a device report, including prefixed app protection ids' {
        $Search = Invoke-Endpoint 'Invoke-ListIntuneSettingSearch' @{ TenantFilter = $script:TenantA; search = 'ion' }
        $Policies = @($Search.Body.Results.Policies | Where-Object URLName -In 'WindowsFeatureUpdateProfiles', 'ManagedAppPolicies')
        $Policies.PolicyId | Sort-Object -Unique | Should -Be @($script:FeatureA, $script:AppProtectionA)

        $Response = Invoke-Endpoint 'Invoke-ListIntuneSettingDevices' (Get-DeviceRequests $Policies)

        $Response.StatusCode | Should -Be 200
        @($Response.Body.Results) | Should -HaveCount 0
        @($Response.Body.Metadata.Warnings) | Should -HaveCount 0
    }

    It 'returns no rows when nothing is cached' {
        $script:Rows = @{}

        $Response = Invoke-Endpoint 'Invoke-ListIntuneSettingSearch' @{ TenantFilter = $script:TenantA; search = 'realtime' }

        $Response.StatusCode | Should -Be 200
        @($Response.Body.Results) | Should -HaveCount 0
    }

    It 'treats <Search> as literal text' -ForEach @(
        @{ Search = "realtime' or 1 eq 1" }
        @{ Search = '.*e' }
        @{ Search = 'real[time' }
        @{ Search = '$filter=(' }
    ) {
        $Response = Invoke-Endpoint 'Invoke-ListIntuneSettingSearch' @{ TenantFilter = $script:TenantA; search = $Search }

        $Response.StatusCode | Should -Be 200
        @($Response.Body.Results) | Should -HaveCount 0
    }
}
