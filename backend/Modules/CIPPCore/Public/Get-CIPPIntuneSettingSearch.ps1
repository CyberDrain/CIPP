function Get-CIPPIntuneSettingSearch {
    <#
    .SYNOPSIS
        Searches cached Intune policies for a setting by name or id
    .DESCRIPTION
        Reads the policy families from Get-CIPPIntunePolicyListDefinitions out of the reporting
        database, flattens each policy with ConvertTo-CIPPIntunePolicySetting and returns one row per
        matching SettingId with the policies that configure it. DeviceCount is left null for
        Add-CIPPIntuneSettingDeviceCount to fill. Administrative
        Templates and Endpoint Security intents are skipped because their settings are not cached.
    .PARAMETER TenantFilter
        Tenant domain name; AllTenants and tenant groups are not supported
    .PARAMETER Search
        Case-insensitive text matched against SettingName and SettingId
    .PARAMETER MaxResults
        When above 0, keeps only the first MaxResults + 1 settings found in the cache, so a caller can tell more matched.
        Policies still accumulate on kept settings. The output is sorted, but when more matched it holds the first
        settings found, not the alphabetically first matches overall.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-CIPPSingleTenantFilter -TenantFilter $_ })]
        [string]$TenantFilter,

        [Parameter(Mandatory = $true)]
        [string]$Search,

        [int]$MaxResults = 0
    )

    $Search = $Search.Trim()
    $UnsupportedFamilies = @('GroupPolicyConfigurations', 'Intents')
    $PolicyDefinitions = @(Get-CIPPIntunePolicyListDefinitions | Where-Object { $_.Id -notin $UnsupportedFamilies })

    $DefinitionIndex = Get-CIPPIntuneDefinitionIndex
    $Groups = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $KeepLimit = if ($MaxResults -gt 0) { $MaxResults + 1 } else { [int]::MaxValue }
    $KeptSettingIds = $null

    try {
        foreach ($Definition in $PolicyDefinitions) {
            $Items = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type $Definition.CacheType | Where-Object { $_.RowKey -notlike '*-Count' })

            foreach ($Item in $Items) {
                try {
                    $Policy = $Item.Data | ConvertFrom-Json -Depth 25 -ErrorAction Stop
                } catch {
                    Write-LogMessage -API 'IntuneSettingSearch' -tenant $TenantFilter -message "Failed to parse cached Intune policy item '$($Item.RowKey)' from '$($Definition.CacheType)': $($_.Exception.Message)" -sev Warning -LogData (Get-CippException -Exception $_)
                    continue
                }
                if ($null -eq $Policy) { continue }

                $ListItem = ConvertTo-CIPPIntunePolicyListItem -Policy $Policy -URLName $Definition.Id -DefaultPolicyTypeName $Definition.PolicyTypeName
                if ($null -eq $ListItem) { continue }

                $TypeLabel = if ($ListItem.PolicyTypeName) {
                    $ListItem.PolicyTypeName
                } elseif ($ListItem.'@odata.type') {
                    $ListItem.'@odata.type' -replace '^#?microsoft\.graph\.', ''
                } else {
                    $Definition.Id
                }
                $SettingParams = @{
                    Policy          = $ListItem
                    URLName         = $Definition.Id
                    PolicyTypeName  = $TypeLabel
                    DefinitionIndex = $DefinitionIndex
                    Search          = $Search
                }
                if ($null -ne $KeptSettingIds) { $SettingParams.SettingIds = $KeptSettingIds }
                $Settings = @(ConvertTo-CIPPIntunePolicySetting @SettingParams)
                if ($Settings.Count -eq 0) { continue }

                foreach ($Setting in $Settings) {
                    if (-not $Groups.ContainsKey($Setting.SettingId)) {
                        if ($Groups.Count -ge $KeepLimit) { continue }
                        $Groups[$Setting.SettingId] = [PSCustomObject]@{
                            SettingId    = $Setting.SettingId
                            SettingName  = $Setting.SettingName
                            Category     = $Setting.Category
                            Policies     = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::OrdinalIgnoreCase)
                            PolicyValues = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
                        }
                        if ($Groups.Count -ge $KeepLimit) {
                            $KeptSettingIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Groups.Keys), [System.StringComparer]::OrdinalIgnoreCase)
                        }
                    }
                    $Group = $Groups[$Setting.SettingId]
                    $PolicyKey = [string]$ListItem.id
                    $Existing = $Group.Policies[$PolicyKey]
                    if ($Existing) {
                        if ($Setting.Value -and $Group.PolicyValues[$PolicyKey].Add($Setting.Value)) {
                            $Existing.Value = if ($Existing.Value) { "$($Existing.Value), $($Setting.Value)" } else { $Setting.Value }
                        }
                        continue
                    }
                    $Group.PolicyValues[$PolicyKey] = [System.Collections.Generic.HashSet[string]]::new()
                    if ($Setting.Value) { $null = $Group.PolicyValues[$PolicyKey].Add($Setting.Value) }
                    $Group.Policies[$PolicyKey] = [PSCustomObject]@{
                        Tenant         = $TenantFilter
                        PolicyId       = [string]$ListItem.id
                        PolicyName     = [string]$ListItem.displayName
                        PolicyTypeName = [string]$ListItem.PolicyTypeName
                        URLName        = $Definition.Id
                        Value          = $Setting.Value
                        DeviceCount    = $null
                    }
                }
            }
            $Items = $null
        }
    } catch {
        Write-LogMessage -API 'IntuneSettingSearch' -tenant $TenantFilter -message "Failed to search Intune settings: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }

    foreach ($Group in ($Groups.Values | Sort-Object -Property SettingName, SettingId)) {
        $Policies = @($Group.Policies.Values | Sort-Object -Property PolicyName)
        [PSCustomObject]@{
            SettingId   = $Group.SettingId
            SettingName = $Group.SettingName
            Category    = $Group.Category
            PolicyTypes = @($Policies.PolicyTypeName | Where-Object { $_ } | Sort-Object -Unique) -join ', '
            PolicyCount = $Policies.Count
            DeviceCount = $null
            Policies    = $Policies
        }
    }
}
