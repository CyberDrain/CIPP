function Invoke-ListIntunePolicyFailures {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Lists the Intune configuration policies (settings catalog, device configuration profiles, administrative templates and endpoint security) that have at least one device in Error or Conflict, from the same report as Intune's Assignment failures view. With policyId it returns that policy's affected devices and its failing settings with error and conflict device counts, naming the other policies that set a conflicting setting where Intune exposes them.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    # Policy id (GUID) to drill into; omit for the list of failing policies
    $PolicyId = $Request.Query.policyId
    # The policy's PolicyBaseTypeName from the list; decides how conflicting policies are looked up
    $PolicyBaseTypeName = $Request.Query.policyBaseTypeName

    # Report shapes (probed 2026-10-30): the summary and per-policy device reports take a PolicyId filter;
    # getConfigurationSettingNonComplianceReport needs PolicyId, DeviceId and UserId together and has no
    # column naming the other policies, so conflict partners come from settingStates.sources (classic
    # profiles) or from the policies applied to the device that share a setting definition (settings catalog).
    $ReportBase = 'https://graph.microsoft.com/beta/deviceManagement/reports'
    $ClassicType = 'Microsoft.Management.Services.Api.DeviceConfiguration'
    $CatalogType = 'DeviceManagementConfigurationPolicy'
    $PolicyTypes = @(
        $ClassicType
        $CatalogType
        'DeviceConfigurationAdmxPolicy'
        'Microsoft.Management.Services.Api.DeviceManagementIntent'
    )
    $URLNames = @{
        $ClassicType                                               = 'deviceConfigurations'
        $CatalogType                                               = 'configurationPolicies'
        'DeviceConfigurationAdmxPolicy'                            = 'groupPolicyConfigurations'
        'Microsoft.Management.Services.Api.DeviceManagementIntent' = 'intents'
    }
    $TypeFilter = ($PolicyTypes | ForEach-Object { "(PolicyBaseTypeName eq '$_')" }) -join ' or '

    # Single-tenant page: the first render arrives before a tenant is picked, answer it with nothing to show
    if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::OK
                Body       = @{ Results = @() }
            })
    }

    if ([string]::IsNullOrWhiteSpace($PolicyId)) {
        try {
            $Rows = Get-CIPPIntuneReportRows -TenantFilter $TenantFilter -Uri "$ReportBase/getConfigurationPolicyNonComplianceSummaryReport" -Filter "($TypeFilter)"
        } catch {
            return ([HttpResponseContext]@{
                    StatusCode = [System.Net.HttpStatusCode]::InternalServerError
                    Body       = @{ Results = "Failed to load the policy failure report: $((Get-CippException -Exception $_).NormalizedError)" }
                })
        }
        $Results = @(foreach ($Row in @($Rows)) {
            if (([int64]$Row.NumberOfErrorDevices + [int64]$Row.NumberOfConflictDevices) -le 0) { continue }
            [PSCustomObject]@{
                id                 = $Row.PolicyId
                displayName        = $Row.PolicyName
                PolicyTypeName     = $Row.UnifiedPolicyType_loc ?? $Row.UnifiedPolicyType
                platform           = $Row.UnifiedPolicyPlatformType_loc ?? $Row.UnifiedPolicyPlatformType
                errorDevices       = [int64]$Row.NumberOfErrorDevices
                conflictDevices    = [int64]$Row.NumberOfConflictDevices
                compliantDevices   = [int64]$Row.NumberOfCompliantDevices
                PolicyBaseTypeName = $Row.PolicyBaseTypeName
                URLName            = $URLNames[[string]$Row.PolicyBaseTypeName]
            }
        })
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::OK
                Body       = @{ Results = @($Results) }
            })
    }

    # The id goes into an OData filter, so only a bare GUID is accepted
    $ParsedId = [guid]::Empty
    if (-not [guid]::TryParse("$PolicyId", [ref]$ParsedId)) {
        return ([HttpResponseContext]@{
                StatusCode = [System.Net.HttpStatusCode]::BadRequest
                Body       = @{ Results = 'policyId must be an Intune policy id.' }
            })
    }
    $PolicyGuid = $ParsedId.ToString()
    $Errors = [ordered]@{}

    $Devices = @()
    try {
        # The helper hands back its rows as one array object, so assign before filtering
        $DeviceRows = Get-CIPPIntuneReportRows -TenantFilter $TenantFilter -Uri "$ReportBase/getConfigurationPolicyNonComplianceReport" -Filter "(PolicyId eq '$PolicyGuid')" -OrderBy @('DeviceName')
        # PolicyStatusEnum comes back as a numeric code; ReportStatus carries the word, as on the device page
        $Devices = @(@($DeviceRows) | Where-Object { $_.ReportStatus -in @('Error', 'Conflict') })
    } catch {
        $Errors['devices'] = "Failed to load devices for policy $($PolicyGuid): $((Get-CippException -Exception $_).NormalizedError)"
    }

    $Settings = [ordered]@{}
    try {
        $SettingRows = Get-CIPPIntuneReportRows -TenantFilter $TenantFilter -Uri "$ReportBase/getConfigurationPolicySettingsDeviceSummaryReport" -Filter "(PolicyId eq '$PolicyGuid')" -OrderBy @('SettingName')
        foreach ($Row in @($SettingRows)) {
            if (([int64]$Row.NumberOfErrorDevices + [int64]$Row.NumberOfConflictDevices) -le 0) { continue }
            $Settings[[string]$Row.SettingName] = [PSCustomObject]@{
                settingName         = $Row.SettingName
                settingId           = $Row.SettingId
                errorDevices        = [int64]$Row.NumberOfErrorDevices
                conflictDevices     = [int64]$Row.NumberOfConflictDevices
                conflictingPolicies = [System.Collections.Generic.List[string]]::new()
            }
        }
    } catch {
        $Errors['settings'] = "Failed to load setting status for policy $($PolicyGuid): $((Get-CippException -Exception $_).NormalizedError)"
    }

    $AddConflict = {
        param($SettingName, $PolicyNames)
        if (-not $Settings.Contains([string]$SettingName)) {
            $Settings[[string]$SettingName] = [PSCustomObject]@{
                settingName         = $SettingName
                settingId           = $null
                errorDevices        = 0
                conflictDevices     = 0
                conflictingPolicies = [System.Collections.Generic.List[string]]::new()
            }
        }
        foreach ($Name in @($PolicyNames)) {
            if ($Name -and $Settings[[string]$SettingName].conflictingPolicies -notcontains $Name) {
                $Settings[[string]$SettingName].conflictingPolicies.Add([string]$Name)
            }
        }
    }

    $ConflictDevices = @($Devices | Where-Object { $_.ReportStatus -eq 'Conflict' })
    if ($ConflictDevices.Count -gt 0) {
        try {
            if ($PolicyBaseTypeName -eq $ClassicType) {
                # Classic profiles: the per-device setting state names every policy that set the setting
                $Requests = foreach ($Device in $ConflictDevices) {
                    [PSCustomObject]@{
                        id     = $Device.IntuneDeviceId
                        method = 'GET'
                        url    = "/deviceManagement/managedDevices/$($Device.IntuneDeviceId)/deviceConfigurationStates/$PolicyGuid/settingStates"
                    }
                }
                foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests))) {
                    if ([int]$Response.status -ge 300) { continue }
                    foreach ($State in @($Response.body.value | Where-Object { $_.state -eq 'conflict' })) {
                        $Others = @($State.sources | Where-Object { $_.id -ne $PolicyGuid } | ForEach-Object { $_.displayName })
                        & $AddConflict ($State.settingName ?? $State.setting) $Others
                    }
                }
            } elseif ($PolicyBaseTypeName -eq $CatalogType) {
                # Settings catalog: no source list from Intune. Pair by the other catalog policies applied to the
                # device whose settings use the same definition as a failing setting of this policy.
                # ponytail: exact for catalog-vs-catalog only; a collision with a classic profile stays unpaired.
                $PolicySettings = @{}
                $GetDefinitionIds = {
                    param($Ids)
                    $Missing = @($Ids | Where-Object { -not $PolicySettings.ContainsKey([string]$_) })
                    if ($Missing.Count -gt 0) {
                        $Requests = foreach ($Id in $Missing) {
                            [PSCustomObject]@{ id = $Id; method = 'GET'; url = "/deviceManagement/configurationPolicies('$Id')?`$expand=settings&`$select=id,name" }
                        }
                        foreach ($Response in @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests))) {
                            if ([int]$Response.status -ge 300) { continue }
                            $PolicySettings[[string]$Response.id] = [PSCustomObject]@{
                                name          = $Response.body.name
                                definitionIds = @($Response.body.settings | ForEach-Object { $_.settingInstance.settingDefinitionId })
                            }
                        }
                    }
                }
                & $GetDefinitionIds @($PolicyGuid)
                $OwnDefinitions = @($PolicySettings[$PolicyGuid].definitionIds)

                foreach ($Device in $ConflictDevices) {
                    $FailingRows = Get-CIPPIntuneReportRows -TenantFilter $TenantFilter -Uri "$ReportBase/getConfigurationSettingNonComplianceReport" -Filter "(PolicyId eq '$PolicyGuid') and (DeviceId eq '$($Device.IntuneDeviceId)') and (UserId eq '$($Device.UserId)')" -OrderBy @('SettingName')
                    $FailingNames = @(@($FailingRows) | ForEach-Object { [string]$_.SettingName })
                    $AppliedRows = Get-CIPPIntuneReportRows -TenantFilter $TenantFilter -Uri "$ReportBase/getConfigurationPoliciesReportForDevice" -Filter "(PolicyBaseTypeName eq '$CatalogType') and (IntuneDeviceId eq '$($Device.IntuneDeviceId)')"
                    $Applied = @(@($AppliedRows) | ForEach-Object { [string]$_.PolicyId } | Where-Object { $_ -and $_ -ne $PolicyGuid } | Select-Object -Unique)
                    & $GetDefinitionIds $Applied
                    foreach ($OtherId in $Applied) {
                        $Other = $PolicySettings[$OtherId]
                        if (-not $Other) { continue }
                        foreach ($Shared in @($OwnDefinitions | Where-Object { $_ -in $Other.definitionIds })) {
                            # the report names the setting by its definition id; fall back to the id itself when it doesn't match
                            $Name = @($FailingNames | Where-Object { $_ -eq $Shared -or $_ -like "*$Shared*" }) | Select-Object -First 1
                            & $AddConflict ($Name ?? $Shared) @($Other.name)
                        }
                    }
                }
            }
        } catch {
            $Errors['conflicts'] = "Failed to resolve conflicting policies: $((Get-CippException -Exception $_).NormalizedError)"
        }
    }

    $StatusCode = Get-CippBulkStatusCode -Total 3 -Failed $Errors.Count
    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{
                Results = [ordered]@{
                    settings = @($Settings.Values)
                    devices  = @($Devices)
                    errors   = $Errors
                }
            }
        })
}
