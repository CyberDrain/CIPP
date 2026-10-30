# Pester tests for Invoke-ListIntunePolicyFailures
# Validates the failing-only list, policyId validation, and the conflict pairing per policy type

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListIntunePolicyFailures.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListIntunePolicyFailures.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }

    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    # Rows per report action name; a scriptblock value throws to simulate a failed report
    function Get-CIPPIntuneReportRows {
        param($TenantFilter, $Uri, $Filter, $Select, $OrderBy, $PageSize)
        $Name = ($Uri -split '/')[-1]
        $script:reportCalls += , @{ Name = $Name; Filter = $Filter }
        $Rows = $script:reports[$Name]
        if ($Rows -is [scriptblock]) { throw 'report down' }
        , @($Rows)
    }
    function New-GraphBulkRequest {
        param($tenantid, $Requests)
        $script:bulkRequests += , @($Requests)
        # The real helper writes each response to the pipeline, not one wrapped array
        @($Requests | ForEach-Object { $script:bulkResponses[[string]$_.id] } | Where-Object { $_ })
    }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')

    function New-Request {
        param($Query)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListIntunePolicyFailures' }
            Headers = @{ Authorization = 'token' }
            Query   = [pscustomobject](@{ tenantFilter = 'contoso.onmicrosoft.com' } + $Query)
        }
    }
}

Describe 'Invoke-ListIntunePolicyFailures' {
    BeforeEach {
        $script:reportCalls = @()
        $script:bulkRequests = @()
        $script:bulkResponses = @{}
        $script:reports = @{}
        $script:policy = '11111111-1111-1111-1111-111111111111'
        $script:other = '22222222-2222-2222-2222-222222222222'
    }

    Context 'list mode' {
        It 'returns only policies with error or conflict devices, mapped to CIPP names' {
            $script:reports['getConfigurationPolicyNonComplianceSummaryReport'] = @(
                [pscustomobject]@{ PolicyId = 'a'; PolicyName = 'Healthy'; PolicyBaseTypeName = 'DeviceManagementConfigurationPolicy'; NumberOfErrorDevices = 0; NumberOfConflictDevices = 0; NumberOfCompliantDevices = 5; UnifiedPolicyType_loc = 'Settings catalog'; UnifiedPolicyPlatformType_loc = 'Windows 10 and later' }
                [pscustomobject]@{ PolicyId = 'b'; PolicyName = 'Broken'; PolicyBaseTypeName = 'Microsoft.Management.Services.Api.DeviceConfiguration'; NumberOfErrorDevices = 2; NumberOfConflictDevices = 1; NumberOfCompliantDevices = 3; UnifiedPolicyType_loc = 'Device restrictions'; UnifiedPolicyPlatformType_loc = 'Windows 10 and later' }
            )

            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{}) -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($response.Body.Results).Count | Should -Be 1
            $response.Body.Results[0].id | Should -Be 'b'
            $response.Body.Results[0].displayName | Should -Be 'Broken'
            $response.Body.Results[0].URLName | Should -Be 'deviceConfigurations'
            $response.Body.Results[0].PolicyTypeName | Should -Be 'Device restrictions'
            $response.Body.Results[0].errorDevices | Should -Be 2
            $reportCalls[0].Filter | Should -Match "PolicyBaseTypeName eq 'DeviceManagementConfigurationPolicy'"
        }

        It 'answers the pre-tenant first render with an empty list' {
            $request = New-Request @{}
            $request.Query.tenantFilter = $null

            $response = Invoke-ListIntunePolicyFailures -Request $request -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($response.Body.Results).Count | Should -Be 0
            $reportCalls.Count | Should -Be 0
        }

        It 'returns 500 with the reason when the report fails' {
            $script:reports['getConfigurationPolicyNonComplianceSummaryReport'] = { throw }

            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{}) -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $response.Body.Results | Should -Match 'report down'
        }
    }

    Context 'detail mode' {
        BeforeEach {
            $script:reports['getConfigurationPolicyNonComplianceReport'] = @(
                [pscustomobject]@{ IntuneDeviceId = 'd1'; UserId = 'u1'; DeviceName = 'PC1'; ReportStatus = 'Conflict' }
                [pscustomobject]@{ IntuneDeviceId = 'd2'; UserId = 'u2'; DeviceName = 'PC2'; ReportStatus = 'Error' }
                [pscustomobject]@{ IntuneDeviceId = 'd3'; UserId = 'u3'; DeviceName = 'PC3'; ReportStatus = 'Succeeded' }
            )
            $script:reports['getConfigurationPolicySettingsDeviceSummaryReport'] = @(
                [pscustomobject]@{ SettingId = 's-ok'; SettingName = 'Fine'; NumberOfErrorDevices = 0; NumberOfConflictDevices = 0 }
                [pscustomobject]@{ SettingId = 's-fw'; SettingName = 'Firewall'; NumberOfErrorDevices = 1; NumberOfConflictDevices = 1 }
            )
        }

        It 'rejects a policyId that is not a GUID' {
            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{ policyId = 'abc' }) -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            $reportCalls.Count | Should -Be 0
        }

        It 'keeps only error and conflict devices and failing settings' {
            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{ policyId = $policy; policyBaseTypeName = 'DeviceConfigurationAdmxPolicy' }) -TriggerMetadata $null

            $response.Body.Results.errors.Count | Should -Be 0 -Because ($response.Body.Results.errors | ConvertTo-Json -Compress)
            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($response.Body.Results.devices).DeviceName | Should -Be @('PC1', 'PC2')
            @($response.Body.Results.settings).Count | Should -Be 1
            $response.Body.Results.settings[0].settingName | Should -Be 'Firewall'
            $response.Body.Results.settings[0].conflictingPolicies | Should -BeNullOrEmpty
            $reportCalls[0].Filter | Should -Be "(PolicyId eq '$policy')"
        }

        It 'names the other policies from settingStates sources for classic profiles' {
            $script:bulkResponses['d1'] = [pscustomobject]@{
                id = 'd1'; status = 200
                body = [pscustomobject]@{ value = @(
                        [pscustomobject]@{ settingName = 'Firewall'; state = 'conflict'; sources = @([pscustomobject]@{ id = $policy; displayName = 'Me' }, [pscustomobject]@{ id = $other; displayName = 'Other profile' }) }
                        [pscustomobject]@{ settingName = 'Fine'; state = 'compliant'; sources = @([pscustomobject]@{ id = $other; displayName = 'Other profile' }) }
                    )
                }
            }

            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{ policyId = $policy; policyBaseTypeName = 'Microsoft.Management.Services.Api.DeviceConfiguration' }) -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($bulkRequests[0]).Count | Should -Be 1
            $bulkRequests[0][0].url | Should -Be "/deviceManagement/managedDevices/d1/deviceConfigurationStates/$policy/settingStates"
            $firewall = $response.Body.Results.settings | Where-Object settingName -EQ 'Firewall'
            @($firewall.conflictingPolicies) | Should -Be @('Other profile')
        }

        It 'pairs settings catalog conflicts with applied policies sharing a setting definition' {
            $script:reports['getConfigurationSettingNonComplianceReport'] = @(
                [pscustomobject]@{ SettingName = 'device_vendor_msft_firewall_enable'; SettingStatus = 6 }
            )
            $script:reports['getConfigurationPoliciesReportForDevice'] = @(
                [pscustomobject]@{ PolicyId = $policy }
                [pscustomobject]@{ PolicyId = $other }
                [pscustomobject]@{ PolicyId = '33333333-3333-3333-3333-333333333333' }
            )
            $script:bulkResponses[$policy] = [pscustomobject]@{ id = $policy; status = 200; body = [pscustomobject]@{ name = 'Me'; settings = @([pscustomobject]@{ settingInstance = [pscustomobject]@{ settingDefinitionId = 'device_vendor_msft_firewall_enable' } }) } }
            $script:bulkResponses[$other] = [pscustomobject]@{ id = $other; status = 200; body = [pscustomobject]@{ name = 'Other catalog'; settings = @([pscustomobject]@{ settingInstance = [pscustomobject]@{ settingDefinitionId = 'device_vendor_msft_firewall_enable' } }) } }
            $script:bulkResponses['33333333-3333-3333-3333-333333333333'] = [pscustomobject]@{ id = '33333333-3333-3333-3333-333333333333'; status = 200; body = [pscustomobject]@{ name = 'Unrelated'; settings = @([pscustomobject]@{ settingInstance = [pscustomobject]@{ settingDefinitionId = 'device_vendor_msft_bitlocker' } }) } }

            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{ policyId = $policy; policyBaseTypeName = 'DeviceManagementConfigurationPolicy' }) -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $settingCall = $reportCalls | Where-Object { $_.Name -eq 'getConfigurationSettingNonComplianceReport' }
            $settingCall.Filter | Should -Be "(PolicyId eq '$policy') and (DeviceId eq 'd1') and (UserId eq 'u1')"
            $paired = $response.Body.Results.settings | Where-Object settingName -EQ 'device_vendor_msft_firewall_enable'
            @($paired.conflictingPolicies) | Should -Be @('Other catalog')
            ($response.Body.Results.settings | Where-Object settingName -EQ 'Firewall').conflictingPolicies | Should -BeNullOrEmpty
        }

        It 'reports a failed sub-call in errors instead of failing the response' {
            $script:reports['getConfigurationPolicySettingsDeviceSummaryReport'] = { throw }

            $response = Invoke-ListIntunePolicyFailures -Request (New-Request @{ policyId = $policy; policyBaseTypeName = 'DeviceConfigurationAdmxPolicy' }) -TriggerMetadata $null

            $response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::MultiStatus)
            $response.Body.Results.errors.settings | Should -Match 'report down'
            @($response.Body.Results.devices).Count | Should -Be 2
        }
    }
}
