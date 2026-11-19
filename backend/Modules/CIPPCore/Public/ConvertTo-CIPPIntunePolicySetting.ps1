function ConvertTo-CIPPIntunePolicySetting {
    <#
    .SYNOPSIS
        Flattens one cached Intune policy into searchable setting rows.
    .DESCRIPTION
        Settings catalog policies yield one row per setting instance, including nested children.
        Custom policies yield one row per OMA-URI. Other policies yield one row per configured
        property, skipping metadata and unset values (null, empty, false and default enum members).
        Each row has SettingId, SettingName, Category and Value.
    .PARAMETER Policy
        The policy object as cached by Set-CIPPDBCacheIntunePolicies.
    .PARAMETER URLName
        The policy family Id from Get-CIPPIntunePolicyListDefinitions.
    .PARAMETER PolicyTypeName
        The policy type label, used as the category when the catalog has none.
    .PARAMETER DefinitionIndex
        The index from Get-CIPPIntuneDefinitionIndex. Catalog rows fall back to raw ids without it.
    .PARAMETER Search
        Only return rows whose SettingName or SettingId contains this text, case-insensitively.
    .PARAMETER SettingIds
        Only return rows with one of these SettingIds. Other rows are skipped before their value is formatted.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Policy,

        [string]$URLName,

        [AllowNull()]
        [string]$PolicyTypeName,

        [AllowNull()]
        $DefinitionIndex,

        [string]$Search,

        [AllowNull()]
        [System.Collections.Generic.HashSet[string]]$SettingIds
    )

    if ($null -eq $Policy) { return }

    $MaxValueLength = 500
    $MaxDepth = 4

    # Graph returns some credentials in plain text (pre-shared keys, kiosk exit codes, key/value app settings) and custom payloads can embed them
    $SecretNamePattern = '(?i)(password|passphrase|passcode|presharedkey|sharedsecret|secret|privatekey|apikey|keymaterial|token|exitcode)$'
    $HiddenProperties = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('payload', 'payloadJson', 'customXml', 'encodedSettingXml', 'configurationXml'),
        [System.StringComparer]::OrdinalIgnoreCase
    )

    $Conceal = {
        param($Owner, [string]$Name, $Value)
        if ($Value -is [bool]) { return $null }
        if ($HiddenProperties.Contains($Name)) { return '(hidden)' }
        if ($Name -match $SecretNamePattern) { return '(secret)' }
        if ($Name -eq 'value' -and [string]($Owner.name ?? $Owner.key) -match $SecretNamePattern) { return '(secret)' }
        $null
    }

    $Redact = $null
    $Redact = {
        param($Value)
        if ($Value -is [System.Management.Automation.PSCustomObject]) {
            $Copy = [ordered]@{}
            foreach ($Property in $Value.PSObject.Properties) {
                $Marker = & $Conceal $Value $Property.Name $Property.Value
                $Copy[$Property.Name] = if ($Marker) { $Marker } else { & $Redact $Property.Value }
            }
            return [PSCustomObject]$Copy
        }
        if ($Value -isnot [string] -and $Value -is [System.Collections.IEnumerable]) {
            return , @(foreach ($Item in $Value) { & $Redact $Item })
        }
        $Value
    }

    $FormatValue = {
        param($Value)
        $Text = if ($Value -is [string]) {
            $Value
        } elseif ($Value -is [bool]) {
            $Value.ToString().ToLowerInvariant()
        } elseif ($Value -is [System.Collections.IEnumerable]) {
            @($Value | Where-Object { $null -ne $_ } | ForEach-Object {
                    if ($_ -is [string] -or $_ -is [ValueType]) { "$_" } else { $_ | ConvertTo-Json -Depth 5 -Compress -WarningAction SilentlyContinue }
                }) -join ', '
        } elseif ($Value -is [ValueType]) {
            "$Value"
        } else {
            $Value | ConvertTo-Json -Depth 5 -Compress -WarningAction SilentlyContinue
        }
        if ($Text.Length -gt $MaxValueLength) { $Text = $Text.Substring(0, $MaxValueLength) + '...' }
        $Text
    }

    $NewRow = {
        param([string]$SettingId, [string]$SettingName, $Category, $Value)
        if ([string]::IsNullOrWhiteSpace($SettingName)) { $SettingName = $SettingId }
        if ($Search -and -not ($SettingName.Contains($Search, [System.StringComparison]::OrdinalIgnoreCase) -or $SettingId.Contains($Search, [System.StringComparison]::OrdinalIgnoreCase))) { return }
        if ($null -ne $SettingIds -and -not $SettingIds.Contains($SettingId)) { return }
        [PSCustomObject]@{
            SettingId   = $SettingId
            SettingName = $SettingName
            Category    = if ([string]::IsNullOrWhiteSpace($Category)) { [string]$PolicyTypeName } else { [string]$Category }
            Value       = [string](& $FormatValue $Value)
        }
    }

    if ($null -ne $Policy.settings -and @($Policy.settings).Where({ $_.settingInstance }).Count -gt 0) {
        $ResolveOption = {
            param($Definition, $Value)
            if ($null -eq $Value) { return $null }
            $Label = $null
            if ($Definition -and $Definition.options -and $Definition.options.TryGetValue("$Value", [ref]$Label) -and $Label) { return $Label }
            "$Value"
        }

        $ResolveSimple = {
            param($SettingValue)
            if ($null -eq $SettingValue) { return $null }
            if ($SettingValue.'@odata.type' -like '*SecretSettingValue') { return '(secret)' }
            $SettingValue.value
        }

        $WalkInstance = $null
        $WalkInstance = {
            param($Instance)
            if ($null -eq $Instance) { return }
            $DefinitionId = [string]$Instance.settingDefinitionId
            $Definition = if ($DefinitionIndex -and $DefinitionId) { $DefinitionIndex[$DefinitionId] } else { $null }
            $Name = $Definition.displayName
            $Category = $Definition.categoryName
            $Children = [System.Collections.Generic.List[object]]::new()
            $Value = $null

            switch -Wildcard ([string]$Instance.'@odata.type') {
                '*ChoiceSettingCollectionInstance' {
                    $Values = foreach ($Choice in @($Instance.choiceSettingCollectionValue)) {
                        if ($null -eq $Choice) { continue }
                        foreach ($Child in @($Choice.children)) { if ($Child) { $Children.Add($Child) } }
                        & $ResolveOption $Definition $Choice.value
                    }
                    $Value = @($Values | Where-Object { $_ }) -join ', '
                }
                '*ChoiceSettingInstance' {
                    $Value = & $ResolveOption $Definition $Instance.choiceSettingValue.value
                    foreach ($Child in @($Instance.choiceSettingValue.children)) { if ($Child) { $Children.Add($Child) } }
                }
                '*SimpleSettingCollectionInstance' {
                    $Value = @(@($Instance.simpleSettingCollectionValue) | ForEach-Object { & $ResolveSimple $_ } | Where-Object { $null -ne $_ }) -join ', '
                }
                '*SimpleSettingInstance' {
                    $Value = & $ResolveSimple $Instance.simpleSettingValue
                }
                '*GroupSettingCollectionInstance' {
                    $Items = @($Instance.groupSettingCollectionValue | Where-Object { $null -ne $_ })
                    foreach ($Item in $Items) {
                        foreach ($Child in @($Item.children)) { if ($Child) { $Children.Add($Child) } }
                    }
                    $Value = if ($Items.Count -eq 1) { '1 item' } else { "$($Items.Count) items" }
                }
                '*GroupSettingInstance' {
                    foreach ($Child in @($Instance.groupSettingValue.children)) { if ($Child) { $Children.Add($Child) } }
                    $Value = 'Configured'
                }
                default {
                    $Value = $null
                }
            }

            if ($DefinitionId) {
                & $NewRow $DefinitionId $Name $Category $Value
            }
            foreach ($Child in $Children) { & $WalkInstance $Child }
        }

        foreach ($Setting in @($Policy.settings)) {
            if ($null -eq $Setting) { continue }
            & $WalkInstance $Setting.settingInstance
        }
        return
    }

    $PlainOmaTypes = @('omaSettingInteger', 'omaSettingBoolean', 'omaSettingFloatingPoint', 'omaSettingDateTime')
    foreach ($OmaSetting in @($Policy.omaSettings)) {
        if ($null -eq $OmaSetting -or [string]::IsNullOrWhiteSpace($OmaSetting.omaUri)) { continue }
        # The cache decrypts encrypted OMA settings and drops isEncrypted/secretReferenceValueId, so only types Intune never encrypts are shown.
        $OmaType = ([string]$OmaSetting.'@odata.type') -replace '^#?microsoft\.graph\.', ''
        $Value = if ($OmaType -notin $PlainOmaTypes -or $OmaSetting.isEncrypted -or $OmaSetting.secretReferenceValueId) { '(encrypted)' } else { $OmaSetting.value }
        & $NewRow $OmaSetting.omaUri $OmaSetting.displayName $null $Value
    }

    $ODataType = ([string]$Policy.'@odata.type') -replace '^#?microsoft\.graph\.', ''
    $TypePrefix = if ($ODataType) { $ODataType } else { $URLName }

    $SkippedProperties = [System.Collections.Generic.HashSet[string]]::new([string[]]@(
            'id', 'displayName', 'name', 'description', 'version', 'createdDateTime', 'lastModifiedDateTime',
            'roleScopeTagIds', 'assignments', 'supportsScopeTags', 'isAssigned', 'settings', 'settingCount',
            'omaSettings', 'deviceManagementApplicabilityRuleOsEdition', 'deviceManagementApplicabilityRuleOsVersion',
            'deviceManagementApplicabilityRuleDeviceMode', 'createdBy', 'lastModifiedBy', 'deployedAppCount',
            'templateReference', 'creationSource', 'platforms', 'technologies', 'priorityMetaData',
            'PolicyTypeName', 'URLName', 'PolicyAssignment', 'PolicyExclude', 'Tenant', 'CacheTimestamp'
        ), [System.StringComparer]::OrdinalIgnoreCase)

    # Graph returns every property of these policies: unset booleans come back false and unset enums as these default members
    $UnsetValues = [System.Collections.Generic.HashSet[string]]::new(
        [string[]]@('notConfigured', 'userDefined', 'deviceDefault', 'browserDefault'),
        [System.StringComparer]::OrdinalIgnoreCase
    )

    $script:CIPPIntuneSettingNameCache ??= [System.Collections.Concurrent.ConcurrentDictionary[string, string]]::new()
    $Humanise = {
        param([string]$Name)
        $Cached = $null
        if ($script:CIPPIntuneSettingNameCache.TryGetValue($Name, [ref]$Cached)) { return $Cached }
        $Spaced = ($Name -creplace '([a-z\d])([A-Z])', '$1 $2') -creplace '([A-Z]+)([A-Z][a-z])', '$1 $2'
        $Words = foreach ($Word in ($Spaced -split '[\s_]+' | Where-Object { $_ })) {
            if ($Word -cmatch '^[A-Z][a-z\d]*$') { $Word.ToLowerInvariant() } else { $Word }
        }
        $Text = $Words -join ' '
        if ($Text) { $Text = $Text.Substring(0, 1).ToUpperInvariant() + $Text.Substring(1) }
        $script:CIPPIntuneSettingNameCache[$Name] = $Text
        $Text
    }

    $WalkProperties = $null
    $WalkProperties = {
        param($Object, [string]$IdPath, [string]$NamePath, [int]$Depth)
        foreach ($Property in $Object.PSObject.Properties) {
            $PropertyName = $Property.Name
            if ($PropertyName -like '*@odata*') { continue }
            if ($Depth -eq 0 -and $SkippedProperties.Contains($PropertyName)) { continue }

            $Value = $Property.Value
            if ($null -eq $Value) { continue }
            if ($Value -is [bool] -and -not $Value) { continue }
            if ($Value -is [string] -and ([string]::IsNullOrWhiteSpace($Value) -or $UnsetValues.Contains($Value))) { continue }

            $SettingId = "$IdPath/$PropertyName"
            $SettingName = if ($NamePath) { "$NamePath > $(& $Humanise $PropertyName)" } else { & $Humanise $PropertyName }

            $Marker = & $Conceal $Object $PropertyName $Value
            if ($Marker) {
                & $NewRow $SettingId $SettingName $null $Marker
                continue
            }
            if ($Value -is [System.Management.Automation.PSCustomObject] -and $Depth -lt $MaxDepth) {
                & $WalkProperties $Value $SettingId $SettingName ($Depth + 1)
                continue
            }
            if ($Value -isnot [string] -and $Value -is [System.Collections.IEnumerable] -and @($Value | Where-Object { $null -ne $_ }).Count -eq 0) { continue }

            & $NewRow $SettingId $SettingName $null (& $Redact $Value)
        }
    }

    & $WalkProperties $Policy $TypePrefix $null 0
}
