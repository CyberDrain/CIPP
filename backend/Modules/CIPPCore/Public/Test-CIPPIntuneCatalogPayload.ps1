function Test-CIPPIntuneCatalogPayload {
    <#
    .SYNOPSIS
        Structural checks for a Settings Catalog policy payload.

    .DESCRIPTION
        Walks the setting tree of a Catalog policy and reports what would stop it deploying. Split out
        of Test-CIPPIntuneTemplate because Catalog is the only type with a nested payload worth
        walking, and because the walk is the part worth testing on its own.

        Returns finding objects rather than writing to a collector, so it can be called and asserted
        against directly.

        The catalog lookups - does this setting still exist, is this choice one of its options - are
        behind IncludeCatalogChecks because they need intuneCollection.json, which is 19MB and costs
        seconds to parse on first use. The structural checks need nothing and always run. That split
        matches what the two are for: the structural checks decide whether a write is refused, the
        catalog lookups only ever produce warnings for someone reading a validation report.

    .PARAMETER Policy
        The parsed Catalog policy payload.

    .PARAMETER IncludeCatalogChecks
        Also resolve each settingDefinitionId against the shipped Intune catalog.

    .EXAMPLE
        Test-CIPPIntuneCatalogPayload -Policy $Policy -IncludeCatalogChecks
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject[]])]
    param(
        [Parameter(Mandatory = $true)]
        $Policy,
        [switch]$IncludeCatalogChecks
    )

    $Findings = [System.Collections.Generic.List[pscustomobject]]::new()
    $NewFinding = {
        param([string]$Severity, [string]$Code, [string]$Path, [string]$Message)
        [pscustomobject]@{ Severity = $Severity; Code = $Code; Path = $Path; Message = $Message }
    }

    if ($Policy.PSObject.Properties.Name -notcontains 'settings') {
        $Findings.Add((& $NewFinding 'Error' 'MissingSettings' 'settings' 'A Settings Catalog policy must carry a settings array.'))
        return @($Findings)
    }

    $Settings = @($Policy.settings)
    if ($Settings.Count -eq 0) {
        $Findings.Add((& $NewFinding 'Warning' 'EmptySettings' 'settings' 'The policy has no settings, so it would deploy as an empty policy.'))
        return @($Findings)
    }

    # Only loaded when asked for, and then once per worker - a drift run validates many templates and
    # they all resolve against the same catalog.
    $Catalog = $null
    if ($IncludeCatalogChecks) {
        $Catalog = Get-CIPPIntuneCatalogIndex
    }

    # A value that is still a replacement token is not a value yet, so nothing about its type or its
    # membership of an option list can be judged here.
    $IsToken = { param($Value) $Value -is [string] -and $Value -match '^%[^%]+%$' }

    function Test-SettingInstance {
        param($Instance, [string]$Path, $Collect, $NewFinding, $Catalog, $IsToken)

        if (-not $Instance) { return }

        if (-not $Instance.'@odata.type') {
            $Collect.Add((& $NewFinding 'Error' 'MissingSettingODataType' $Path 'Setting instance is missing @odata.type. Intune rejects a policy whose settings do not declare their type.'))
        }

        $DefinitionId = $Instance.settingDefinitionId
        if ([string]::IsNullOrWhiteSpace($DefinitionId)) {
            $Collect.Add((& $NewFinding 'Error' 'MissingSettingDefinitionId' $Path 'Setting instance is missing settingDefinitionId, so Intune cannot tell which setting it configures.'))
        } elseif ($Catalog -and -not $Catalog.ContainsKey($DefinitionId)) {
            $Collect.Add((& $NewFinding 'Warning' 'UnknownSetting' $Path "Setting '$DefinitionId' is not in the shipped Intune catalog. It may have been retired, or the catalog may predate it."))
        }

        $Definition = if ($Catalog -and $DefinitionId) { $Catalog[$DefinitionId] } else { $null }

        # choiceSettingValue - a single choice, whose children are further instances.
        if ($Instance.PSObject.Properties.Name -contains 'choiceSettingValue' -and $Instance.choiceSettingValue) {
            $Choice = $Instance.choiceSettingValue
            if ($null -eq $Choice.value) {
                $Collect.Add((& $NewFinding 'Error' 'MissingChoiceValue' "$Path.choiceSettingValue" 'Choice setting has no value.'))
            } elseif ($Definition -and $Definition.options -and -not (& $IsToken $Choice.value)) {
                if ($Choice.value -notin @($Definition.options.id)) {
                    $Collect.Add((& $NewFinding 'Warning' 'UnknownChoiceValue' "$Path.choiceSettingValue" "Value '$($Choice.value)' is not one of the options the catalog lists for '$DefinitionId'."))
                }
            }
            $Index = 0
            foreach ($Child in @($Choice.children)) {
                Test-SettingInstance -Instance $Child -Path "$Path.choiceSettingValue.children[$Index]" -Collect $Collect -NewFinding $NewFinding -Catalog $Catalog -IsToken $IsToken
                $Index++
            }
        }

        # simpleSettingValue - a scalar. Its own @odata.type carries the value type.
        if ($Instance.PSObject.Properties.Name -contains 'simpleSettingValue' -and $Instance.simpleSettingValue) {
            if (-not $Instance.simpleSettingValue.'@odata.type') {
                $Collect.Add((& $NewFinding 'Error' 'MissingValueODataType' "$Path.simpleSettingValue" 'Simple setting value is missing @odata.type, so Intune cannot tell whether it is a string, an integer or a secret.'))
            }
        }

        # groupSettingCollectionValue - repeating groups, each holding its own children.
        foreach ($Property in @('groupSettingCollectionValue', 'choiceSettingCollectionValue')) {
            if ($Instance.PSObject.Properties.Name -notcontains $Property) { continue }

            # Intune enforces how many entries a collection may hold and rejects the entire policy
            # when it is exceeded, naming only the group - so a template with one row too many
            # deploys nowhere and the error does not say which setting to fix. The ASR rules group
            # allows exactly one, which is easy to exceed and impossible to guess.
            if ($Definition) {
                $Count = @($Instance.$Property).Count
                # Cast rather than type-test: ConvertFrom-Json types a whole number as Int64 or
                # Int32 depending on its size, so testing for [int] skips the check on exactly the
                # values it is meant to catch - silently, which is the worst way for it to fail.
                $Maximum = if ($null -ne $Definition.maximumCount) { [int]$Definition.maximumCount } else { $null }
                $Minimum = if ($null -ne $Definition.minimumCount) { [int]$Definition.minimumCount } else { $null }

                if ($null -ne $Maximum -and $Maximum -gt 0 -and $Count -gt $Maximum) {
                    $Collect.Add((& $NewFinding 'Error' 'TooManyCollectionEntries' "$Path.$Property" "'$DefinitionId' holds $Count entries but Intune allows at most $Maximum. The whole policy is rejected on deployment."))
                }
                if ($null -ne $Minimum -and $Count -lt $Minimum) {
                    $Collect.Add((& $NewFinding 'Error' 'TooFewCollectionEntries' "$Path.$Property" "'$DefinitionId' holds $Count entries but Intune requires at least $Minimum."))
                }
            }

            $Index = 0
            foreach ($Entry in @($Instance.$Property)) {
                $EntryPath = "$Path.$Property[$Index]"
                if ($Property -eq 'choiceSettingCollectionValue' -and $null -eq $Entry.value) {
                    $Collect.Add((& $NewFinding 'Error' 'MissingChoiceValue' $EntryPath 'Choice collection entry has no value.'))
                }
                # Intune refuses a group entry that configures nothing - "SettingGroupValue should
                # not be empty" - and the message names only the group, so a template built with an
                # empty one deploys nowhere and gives no clue which setting to fix.
                if ($Property -eq 'groupSettingCollectionValue' -and @($Entry.children).Count -eq 0) {
                    $Collect.Add((& $NewFinding 'Error' 'EmptyGroupEntry' $EntryPath "'$DefinitionId' has a group entry with no settings in it. Intune rejects the whole policy rather than the entry."))
                }

                $ChildIndex = 0
                foreach ($Child in @($Entry.children)) {
                    Test-SettingInstance -Instance $Child -Path "$EntryPath.children[$ChildIndex]" -Collect $Collect -NewFinding $NewFinding -Catalog $Catalog -IsToken $IsToken
                    $ChildIndex++
                }
                $Index++
            }
        }

        # groupSettingValue - a single group, rejected just as firmly when it holds nothing.
        if ($Instance.PSObject.Properties.Name -contains 'groupSettingValue' -and $Instance.groupSettingValue) {
            if (@($Instance.groupSettingValue.children).Count -eq 0) {
                $Collect.Add((& $NewFinding 'Error' 'EmptyGroupEntry' "$Path.groupSettingValue" "'$DefinitionId' is a group with no settings in it. Intune rejects the whole policy rather than the group."))
            }
            $ChildIndex = 0
            foreach ($Child in @($Instance.groupSettingValue.children)) {
                Test-SettingInstance -Instance $Child -Path "$Path.groupSettingValue.children[$ChildIndex]" -Collect $Collect -NewFinding $NewFinding -Catalog $Catalog -IsToken $IsToken
                $ChildIndex++
            }
        }

        # simpleSettingCollectionValue - repeating scalars, each typed individually.
        if ($Instance.PSObject.Properties.Name -contains 'simpleSettingCollectionValue') {
            $Index = 0
            foreach ($Entry in @($Instance.simpleSettingCollectionValue)) {
                if (-not $Entry.'@odata.type') {
                    $Collect.Add((& $NewFinding 'Error' 'MissingValueODataType' "$Path.simpleSettingCollectionValue[$Index]" 'Simple setting collection entry is missing @odata.type.'))
                }
                $Index++
            }
        }
    }

    $Index = 0
    foreach ($Setting in $Settings) {
        $Path = "settings[$Index]"
        if (-not $Setting.settingInstance) {
            $Findings.Add((& $NewFinding 'Error' 'MissingSettingInstance' $Path 'Setting entry has no settingInstance.'))
        } else {
            Test-SettingInstance -Instance $Setting.settingInstance -Path "$Path.settingInstance" -Collect $Findings -NewFinding $NewFinding -Catalog $Catalog -IsToken $IsToken
        }
        $Index++
    }

    return @($Findings)
}
