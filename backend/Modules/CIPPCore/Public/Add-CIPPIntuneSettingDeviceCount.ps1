function Add-CIPPIntuneSettingDeviceCount {
    <#
    .SYNOPSIS
        Sets DeviceCount on Intune setting search results from the reporting database
    .DESCRIPTION
        For each result and each of its Policies, DeviceCount is the number of distinct managed devices (by Intune
        device id) in the cached device statuses (device configuration and compliance policies)
        or cached device reports (settings catalog). A settings catalog row without a device id counts by device name,
        as the same device as a row with an id and that name. It is null when none of the policies has cached device data.
        Only row keys are read, and only for the policies in the given results.
    .PARAMETER TenantFilter
        The tenant the results were searched in
    .PARAMETER Results
        Rows from Get-CIPPIntuneSettingSearch; they are updated in place
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [AllowEmptyCollection()]
        [object[]]$Results
    )

    # Above this many policies of one family, one range read of the family beats a read per policy
    $PerPolicyReadLimit = 5
    $CatalogDevicesType = 'IntuneConfigurationPolicyDevices'

    $Results = @($Results | Where-Object { $_ })
    if ($Results.Count -eq 0) { return }

    $TypeByUrlName = @{}
    foreach ($Definition in @(Get-CIPPIntunePolicyListDefinitions)) {
        if ($Definition.Id -eq 'ConfigurationPolicies') {
            $TypeByUrlName[$Definition.Id] = $CatalogDevicesType
        } elseif ($Definition.FetchDeviceStatuses) {
            $TypeByUrlName[$Definition.Id] = $Definition.CacheType
        }
    }

    $Partition = (Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1).defaultDomainName ?? $TenantFilter
    $SafePartition = ConvertTo-CIPPODataFilterValue -Value $Partition -Type String

    $Wanted = @{}
    foreach ($Policy in @($Results.Policies | Where-Object { $_ })) {
        $Type = $TypeByUrlName[[string]$Policy.URLName]
        if (-not $Type -or "$($Policy.PolicyId)" -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') { continue }
        if (-not $Wanted.ContainsKey($Type)) {
            $Wanted[$Type] = [PSCustomObject]@{
                Type      = $Type
                PolicyIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            }
        }
        $null = $Wanted[$Type].PolicyIds.Add([string]$Policy.PolicyId)
    }

    $NewDeviceSet = {
        [PSCustomObject]@{
            Ids         = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            NamesWithId = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            NamesOnly   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
    }
    # A row with only a device name is the same device as a row with an id and that name
    $CountDevices = {
        param($Set)
        $Unmatched = [System.Collections.Generic.HashSet[string]]::new($Set.NamesOnly, [System.StringComparer]::OrdinalIgnoreCase)
        $Unmatched.ExceptWith($Set.NamesWithId)
        $Set.Ids.Count + $Unmatched.Count
    }

    # policy id -> device set; a policy is present once any row of it, data or count, is cached
    $DevicesByPolicy = @{}
    $Table = Get-CippTable -tablename 'CippReportingDB'
    foreach ($Read in $Wanted.Values) {
        $Ranges = if ($Read.PolicyIds.Count -le $PerPolicyReadLimit) {
            foreach ($PolicyId in $Read.PolicyIds) { [PSCustomObject]@{ From = "$($Read.Type)_$PolicyId-"; To = "$($Read.Type)_$PolicyId." } }
        } else {
            [PSCustomObject]@{ From = "$($Read.Type)_"; To = "$($Read.Type)``" }
        }
        foreach ($Range in @($Ranges)) {
            $Filter = "PartitionKey eq '{0}' and RowKey ge '{1}' and RowKey lt '{2}'" -f $SafePartition, (ConvertTo-CIPPODataFilterValue -Value $Range.From -Type String), (ConvertTo-CIPPODataFilterValue -Value $Range.To -Type String)
            foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter $Filter -Property @('PartitionKey', 'RowKey'))) {
                $Rest = "$($Row.RowKey)".Substring($Read.Type.Length + 1)
                if ($Rest.Length -lt 38 -or $Rest[36] -ne '-') { continue }
                $PolicyId = $Rest.Substring(0, 36)
                if (-not $Read.PolicyIds.Contains($PolicyId)) { continue }
                $ItemKey = $Rest.Substring(37) -replace '-part\d+$'
                if (-not $DevicesByPolicy.ContainsKey($PolicyId)) { $DevicesByPolicy[$PolicyId] = & $NewDeviceSet }
                if ($ItemKey -eq 'Count') { continue }
                $Devices = $DevicesByPolicy[$PolicyId]
                if ($Read.Type -eq $CatalogDevicesType) {
                    # Catalog rows are keyed "<device id>|<device name>|<user>"; a device name may itself hold '|'
                    $First = $ItemKey.IndexOf('|')
                    $Last = $ItemKey.LastIndexOf('|')
                    if ($First -lt 0 -or $Last -le $First) { continue }
                    $DeviceId = $ItemKey.Substring(0, $First)
                    $DeviceName = $ItemKey.Substring($First + 1, $Last - $First - 1)
                    if ($DeviceId) {
                        $null = $Devices.Ids.Add($DeviceId)
                        if ($DeviceName) { $null = $Devices.NamesWithId.Add($DeviceName) }
                    } elseif ($DeviceName) {
                        $null = $Devices.NamesOnly.Add($DeviceName)
                    }
                } else {
                    # deviceStatuses ids end in "_<device id>"
                    $DeviceId = $ItemKey.Substring($ItemKey.LastIndexOf('_') + 1)
                    if ($DeviceId) { $null = $Devices.Ids.Add($DeviceId) }
                }
            }
        }
    }

    foreach ($Result in $Results) {
        $RowDevices = $null
        foreach ($Policy in @($Result.Policies | Where-Object { $_ })) {
            $Devices = $DevicesByPolicy[[string]$Policy.PolicyId]
            $Count = $null
            if ($null -ne $Devices) {
                $Count = & $CountDevices $Devices
                if ($null -eq $RowDevices) { $RowDevices = & $NewDeviceSet }
                $RowDevices.Ids.UnionWith($Devices.Ids)
                $RowDevices.NamesWithId.UnionWith($Devices.NamesWithId)
                $RowDevices.NamesOnly.UnionWith($Devices.NamesOnly)
            }
            $Policy | Add-Member -NotePropertyName DeviceCount -NotePropertyValue $Count -Force
        }
        $Result | Add-Member -NotePropertyName DeviceCount -NotePropertyValue ($null -eq $RowDevices ? $null : (& $CountDevices $RowDevices)) -Force
    }
}
