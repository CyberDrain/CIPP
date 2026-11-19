function Invoke-ListIntuneSettingDevices {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Endpoint.MEM.Read
    .DESCRIPTION
        Lists the devices that have any of the given Intune policies, with each device's deployment status for that policy, for one tenant. Device configuration and compliance policies are read from the reporting database cache when it holds their device statuses, settings catalog policies when it holds their device report, other policies (or policies with nothing cached) are read live. Each row says which in Source (Cache or Live). A device name Intune leaves blank is filled from the managed device (reporting cache first, then Graph). Policy types Intune has no per-device status for (update profiles, hardware configurations, app protection) return no rows. A policy that fails to load does not fail the request: its message is in Metadata.Warnings. At most 50 policies can be requested at once; split larger sets across requests.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $MaxPolicies = 50

    $TenantFilter = $Request.Query.tenantFilter
    # Comma-separated <URLName>:<PolicyId> pairs, e.g. deviceConfigurations:<guid>,configurationPolicies:<guid>
    $Policies = $Request.Query.Policies

    if (-not (Test-CIPPSingleTenantFilter -TenantFilter $TenantFilter)) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'A single tenant is required.' }
            })
    }

    $Definitions = @(Get-CIPPIntunePolicyListDefinitions)
    $Requested = [System.Collections.Generic.List[object]]::new()
    $Seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Invalid = [System.Collections.Generic.List[string]]::new()
    foreach ($Entry in @("$Policies" -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
        $URLName, $PolicyId = $Entry -split ':', 2
        $Definition = $Definitions | Where-Object { $_.Id -eq $URLName } | Select-Object -First 1
        # App protection ids carry a type prefix (T_<guid>, A_<guid>)
        if (-not $Definition -or "$PolicyId" -notmatch '^([A-Za-z]_)?[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
            $Invalid.Add($Entry)
            continue
        }
        if ($Seen.Add("$($Definition.Id):$PolicyId")) {
            $Requested.Add([PSCustomObject]@{ URLName = $URLName; PolicyId = $PolicyId; Definition = $Definition })
        }
    }

    if ($Invalid.Count -gt 0 -or $Requested.Count -eq 0) {
        $Message = if ($Invalid.Count -gt 0) { "Invalid policies: $($Invalid -join ', '). Each must be <URLName>:<PolicyId> with a known policy type and a policy id." } else { 'At least one policy is required as <URLName>:<PolicyId>.' }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = $Message }
            })
    }

    if ($Requested.Count -gt $MaxPolicies) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Too many policies: $($Requested.Count) requested, at most $MaxPolicies are allowed per request." }
            })
    }

    $DeviceStatusTypes = @('deviceConfigurations', 'deviceCompliancePolicies', 'mobileAppConfigurations')
    $MaxDeviceLookups = 100
    $GuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$'
    $Unnamed = [System.Collections.Generic.List[object]]::new()

    $Rows = [System.Collections.Generic.List[object]]::new()
    $Warnings = [System.Collections.Generic.List[string]]::new()
    foreach ($Policy in $Requested) {
        $Source = 'Live'
        $CachedStatuses = $null
        if ($Policy.Definition.FetchDeviceStatuses) {
            try {
                $CachedStatuses = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type "$($Policy.Definition.CacheType)_$($Policy.PolicyId)" |
                        Where-Object { $_.RowKey -notlike '*-Count' } |
                        ForEach-Object { try { $_.Data | ConvertFrom-Json -ErrorAction Stop } catch { $null } } |
                        Where-Object { $_ })
            } catch {
                $CachedStatuses = $null
            }
            # The cache writes nothing for a policy without device statuses, so an empty read is not authoritative
            if ($CachedStatuses.Count -gt 0) { $Source = 'Cache' }
        }

        $CachedReportRows = $null
        if ($Policy.Definition.Id -eq 'ConfigurationPolicies') {
            try {
                $CachedItems = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type "IntuneConfigurationPolicyDevices_$($Policy.PolicyId)")
                # The count row is written with every successful report, so its presence makes an empty read authoritative
                if (@($CachedItems | Where-Object { $_.RowKey -like '*-Count' }).Count -gt 0) {
                    $CachedReportRows = @($CachedItems |
                            Where-Object { $_.RowKey -notlike '*-Count' } |
                            ForEach-Object { try { $_.Data | ConvertFrom-Json -ErrorAction Stop } catch { $null } } |
                            Where-Object { $_ })
                    $Source = 'Cache'
                }
            } catch {
                $CachedReportRows = $null
            }
        }

        $GraphType = $DeviceStatusTypes | Where-Object { $_ -eq $Policy.Definition.Id } | Select-Object -First 1

        $DeviceIds = @()
        try {
            $StatusParams = @{
                TenantFilter = $TenantFilter
                Type         = $Policy.Definition.Id
                Id           = $Policy.PolicyId
                DevicesOnly  = $true
            }
            if ($GraphType) {
                $RawStatuses = if ($Source -eq 'Cache') { $CachedStatuses } else {
                    $Base = if ($GraphType -eq 'mobileAppConfigurations') { 'deviceAppManagement' } else { 'deviceManagement' }
                    try {
                        New-GraphGetRequest -uri "https://graph.microsoft.com/beta/$Base/$GraphType('$($Policy.PolicyId)')/deviceStatuses" -tenantid $TenantFilter
                    } catch {
                        throw "Failed to load deployment status for $GraphType $($Policy.PolicyId): $((Get-CippException -Exception $_).NormalizedError)"
                    }
                }
                # Intune gives the system and user rows of one device the same id; the cache keeps only the first, so live does too
                $SeenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
                $StatusParams.DeviceStatuses = @($RawStatuses | Where-Object { $_ -and ($null -eq $_.id -or $SeenIds.Add("$($_.id)")) })
                # The last '_' segment of a status row id is the Intune managed device id
                $DeviceIds = @($StatusParams.DeviceStatuses | ForEach-Object { @("$($_.id)" -split '_')[-1] })
            } elseif ($Policy.Definition.Id -eq 'ConfigurationPolicies') {
                $StatusParams.ReportRows = if ($null -ne $CachedReportRows) { $CachedReportRows } else {
                    # Read here rather than in Get-CIPPIntuneDeploymentStatus to keep each row's device id
                    try {
                        @(Get-CIPPIntuneReportRows -TenantFilter $TenantFilter -Uri 'https://graph.microsoft.com/beta/deviceManagement/reports/getConfigurationPolicyDevicesReport' -Filter "($(Get-CIPPIntunePolicyReportTypeFilter)) and (PolicyId eq '$($Policy.PolicyId)')" -OrderBy @())
                    } catch {
                        throw "Failed to load deployment status for configurationPolicies $($Policy.PolicyId): $((Get-CippException -Exception $_).NormalizedError)"
                    }
                }
                $DeviceIds = @($StatusParams.ReportRows | ForEach-Object { "$($_.IntuneDeviceId)" })
            }
            $Status = Get-CIPPIntuneDeploymentStatus @StatusParams
        } catch {
            $Warnings.Add($_.Exception.Message)
            continue
        }

        $Devices = @($Status.Devices)
        for ($i = 0; $i -lt $Devices.Count; $i++) {
            $Device = $Devices[$i]
            if (-not $Device) { continue }
            $Row = [PSCustomObject]@{
                PolicyId          = $Policy.PolicyId
                URLName           = $Policy.URLName
                DeviceName        = $Device.DeviceName
                UserPrincipalName = $Device.UserPrincipalName
                Status            = $Device.Status
                StatusDetail      = $Device.StatusDetail
                Platform          = $Device.Platform
                LastReported      = $Device.LastReported
                Source            = $Source
            }
            # deviceStatuses report a device's own (device-targeted) status with no user
            if ($GraphType -and [string]::IsNullOrEmpty($Row.UserPrincipalName)) { $Row.UserPrincipalName = 'System account' }
            $DeviceId = if ($DeviceIds.Count -eq $Devices.Count) { $DeviceIds[$i] }
            if ([string]::IsNullOrWhiteSpace($Row.DeviceName) -and "$DeviceId" -match $GuidPattern) {
                $Unnamed.Add([PSCustomObject]@{ Row = $Row; DeviceId = "$DeviceId" })
            }
            $Rows.Add($Row)
        }
    }

    # Intune can leave deviceDisplayName empty on status rows, so the name comes from the managed device
    if ($Unnamed.Count -gt 0) {
        $Wanted = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Unnamed.DeviceId), [System.StringComparer]::OrdinalIgnoreCase)
        $ManagedDevices = @{}
        try {
            foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'ManagedDevices')) {
                if (-not $Wanted.Contains(("$($Item.RowKey)" -replace '^ManagedDevices-'))) { continue }
                $ManagedDevice = try { $Item.Data | ConvertFrom-Json -ErrorAction Stop } catch { $null }
                if ($ManagedDevice.id -and $ManagedDevice.deviceName) { $ManagedDevices[$ManagedDevice.id] = $ManagedDevice }
            }
        } catch {
            $ManagedDevices = @{}
        }
        $LiveIds = @($Wanted | Where-Object { -not $ManagedDevices.ContainsKey($_) } | Select-Object -First $MaxDeviceLookups)
        if ($LiveIds.Count -gt 0) {
            try {
                $DeviceRequests = foreach ($Id in $LiveIds) {
                    @{ id = $Id; method = 'GET'; url = "/deviceManagement/managedDevices/$($Id)?`$select=id,deviceName,operatingSystem" }
                }
                foreach ($Result in @(New-GraphBulkRequest -Requests @($DeviceRequests) -tenantid $TenantFilter)) {
                    if ($Result.body.id -and $Result.body.deviceName) { $ManagedDevices[$Result.body.id] = $Result.body }
                }
            } catch {
                Write-Warning "Could not look up managed device names for $($TenantFilter): $($_.Exception.Message)"
            }
        }
        foreach ($Entry in $Unnamed) {
            $ManagedDevice = $ManagedDevices[$Entry.DeviceId]
            if (-not $ManagedDevice) { continue }
            $Entry.Row.DeviceName = $ManagedDevice.deviceName
            if ([string]::IsNullOrWhiteSpace($Entry.Row.Platform)) { $Entry.Row.Platform = $ManagedDevice.operatingSystem }
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @{
                Results  = @($Rows)
                Metadata = @{ Warnings = @($Warnings) }
            }
        })
}
