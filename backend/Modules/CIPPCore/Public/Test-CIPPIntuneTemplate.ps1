function Test-CIPPIntuneTemplate {
    <#
    .SYNOPSIS
        Checks an Intune template for the things that stop it deploying.

    .DESCRIPTION
        Set-CIPPIntunePolicy does not validate: it dispatches on template type, strips the properties
        Graph rejects, and lets Graph refuse whatever is left. That is fine when Graph refuses, but a
        type the dispatch switch does not name sends nothing at all and still reports success, so a
        broken template can sit in the list looking deployed until someone checks the tenant.

        This replays the preconditions the deploy path depends on, without calling Graph, so the same
        problems surface when a template is stored, imported or edited instead of on a tenant. It is
        deliberately the only place those preconditions are written down - the store paths, the import
        path and the deploy path all call this rather than re-implementing a subset each.

        Findings are graded, and the grading matters:

          Error   - deployment cannot succeed. Callers refuse the write.
          Warning - deployment can succeed but may not do what the template says. Never blocks, because
                    the catalog ships with the release and lags Intune: a setting Microsoft added last
                    week is legitimately absent from it, and refusing that template would be wrong.

        Passing TenantFilter adds the checks that need a tenant to answer - whether the replacement
        variables resolve, and whether an Endpoint Security template keeps its settings once filtered
        to what the tenant offers. Without it the result is purely static and needs no Graph access.

    .PARAMETER RawJSON
        The policy payload, as a JSON string or an already parsed object.

    .PARAMETER TemplateType
        The template's recorded Type. Inferred from the payload when empty, the same way the read
        paths infer it, so a template stored before Type existed still validates.

    .PARAMETER DisplayName
        The template's Displayname column. Used to resolve the deployed policy name the way
        Set-CIPPIntunePolicy resolves it, which for some types comes from the payload instead.

    .PARAMETER TenantFilter
        Tenant to run the tenant-aware checks against. Omit for static validation only.

    .PARAMETER IncludeCatalogChecks
        Also resolve every settingDefinitionId in a Catalog policy against the shipped Intune catalog.
        Off by default because that catalog is 19MB and costs seconds to parse the first time a worker
        needs it, which is not a price worth paying on every save for checks that only ever warn.

    .EXAMPLE
        $Result = Test-CIPPIntuneTemplate -RawJSON $Template.RAWJson -TemplateType $Template.Type -DisplayName $Template.Displayname
        if (-not $Result.IsValid) { throw ($Result.Errors -join '; ') }

    .EXAMPLE
        Test-CIPPIntuneTemplate -RawJSON $Raw -TemplateType 'Catalog' -TenantFilter 'contoso.onmicrosoft.com'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        $RawJSON,
        [string]$TemplateType,
        [string]$DisplayName,
        [string]$TenantFilter,
        [switch]$IncludeCatalogChecks
    )

    $Findings = [System.Collections.Generic.List[pscustomobject]]::new()
    $Add = {
        param([string]$Severity, [string]$Code, [string]$Path, [string]$Message)
        $Findings.Add([pscustomobject]@{
                Severity = $Severity
                Code     = $Code
                Path     = $Path
                Message  = $Message
            })
    }

    # ---------------------------------------------------------------------
    # The payload has to be readable before anything else can be checked.
    # ---------------------------------------------------------------------
    $Policy = $null
    if ($RawJSON -is [string]) {
        if ([string]::IsNullOrWhiteSpace($RawJSON)) {
            & $Add 'Error' 'EmptyPayload' '' 'The template has no policy payload.'
        } else {
            try {
                $Policy = $RawJSON | ConvertFrom-Json -Depth 100 -ErrorAction Stop
            } catch {
                & $Add 'Error' 'InvalidJson' '' "The policy payload is not valid JSON: $($_.Exception.Message)"
            }
        }
    } else {
        $Policy = $RawJSON
    }

    if (-not $Policy) {
        if ($Findings.Count -eq 0) {
            & $Add 'Error' 'EmptyPayload' '' 'The template has no policy payload.'
        }
        return [pscustomobject]@{
            IsValid     = $false
            Type        = $null
            DisplayName = $DisplayName
            Findings    = @($Findings)
            Errors      = @($Findings | Where-Object { $_.Severity -eq 'Error' } | ForEach-Object { $_.Message })
            Warnings    = @()
        }
    }

    # ---------------------------------------------------------------------
    # Type. Everything below dispatches on it, and an unresolved type is the
    # failure that otherwise reports success, so it is checked first.
    # ---------------------------------------------------------------------
    $ResolvedType = Get-CIPPIntuneTemplateType -Type $TemplateType -RawJson $RawJSON
    $DeployableTypes = Get-CIPPIntuneDeployableType

    if (-not $ResolvedType) {
        & $Add 'Error' 'UnknownType' 'Type' 'The template type could not be determined from the stored type or the payload. Re-import or recapture the template.'
    } elseif ($ResolvedType -notin $DeployableTypes) {
        & $Add 'Error' 'UndeployableType' 'Type' "Template type '$ResolvedType' cannot be deployed. Deployment supports: $($DeployableTypes -join ', ')."
    } elseif (-not $TemplateType) {
        & $Add 'Warning' 'InferredType' 'Type' "The template has no stored type; '$ResolvedType' was inferred from the payload. Re-import it to record the type."
    }

    # The name the policy actually deploys under, which for some types is read from the payload and
    # ignores the Displayname column entirely.
    $ResolvedName = if ($ResolvedType) {
        Get-CIPPIntunePolicyName -TemplateType $ResolvedType -RawJSON $RawJSON -DisplayName $DisplayName
    } else {
        $DisplayName
    }
    if ([string]::IsNullOrWhiteSpace($ResolvedName)) {
        & $Add 'Error' 'NoDisplayName' 'displayName' 'The template resolves to no policy name, so the deployed policy would be unnamed.'
    }

    # ---------------------------------------------------------------------
    # Per-type preconditions, mirroring what each branch of the deploy switch
    # reads before it builds its request.
    # ---------------------------------------------------------------------
    switch ($ResolvedType) {
        'AppProtection' {
            # The concrete Graph collection has to be resolvable or there is nowhere to post to.
            # Set-CIPPIntunePolicy throws on this; catching it here means it is caught on save.
            if (-not (Get-CIPPAppProtectionPolicyUrl -Policy $Policy)) {
                & $Add 'Error' 'AppProtectionPlatformUnknown' '@odata.type' 'This App Protection template identifies no platform - it carries no @odata.type, no @odata.context and no platform-specific settings - so the collection to deploy it to cannot be determined.'
            }
        }
        'deviceCompliancePolicies' {
            # Deployment assigns straight into this property to strip an annotation off it. On a
            # parsed payload that has no such property the assignment throws, so a compliance policy
            # captured without it fails at deploy time with an unrelated-looking error.
            if ($Policy.PSObject.Properties.Name -notcontains 'scheduledActionsForRule') {
                & $Add 'Error' 'MissingScheduledActions' 'scheduledActionsForRule' 'A compliance policy must carry scheduledActionsForRule. Deployment reads this property directly and fails without it.'
            }
            if (-not $Policy.'@odata.type') {
                & $Add 'Warning' 'MissingODataType' '@odata.type' 'No @odata.type, so an existing policy of this type cannot be matched by type and a duplicate may be created.'
            }
        }
        'Device' {
            # deviceConfigurations is polymorphic - without the discriminator Graph cannot tell which
            # concrete configuration type is being created.
            if (-not $Policy.'@odata.type') {
                & $Add 'Error' 'MissingODataType' '@odata.type' 'A device configuration must carry @odata.type. Graph cannot determine the policy type without it.'
            }
        }
        'Admin' {
            # The payload is posted to updateDefinitionValues, which applies whatever 'added' holds.
            $HasAdded = $Policy.PSObject.Properties.Name -contains 'added'
            if (-not $HasAdded) {
                & $Add 'Error' 'MissingDefinitionValues' 'added' 'An administrative template must carry an "added" array of definition values. Deployment posts this to updateDefinitionValues and would apply nothing without it.'
            } elseif (@($Policy.added).Count -eq 0) {
                & $Add 'Warning' 'EmptyDefinitionValues' 'added' 'The "added" array is empty, so this template would create a policy with no configured settings.'
            }
        }
        'Catalog' {
            foreach ($Finding in (Test-CIPPIntuneCatalogPayload -Policy $Policy -IncludeCatalogChecks:$IncludeCatalogChecks)) {
                $Findings.Add($Finding)
            }
        }
        default {
            # The Windows update profile types carry no structural requirement beyond a resolvable
            # name, which is checked above for every type.
        }
    }

    # ---------------------------------------------------------------------
    # Tenant-aware checks. Skipped entirely without a tenant.
    # ---------------------------------------------------------------------
    if ($TenantFilter) {
        try {
            $Replaced = Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text ($RawJSON -is [string] ? $RawJSON : (ConvertTo-Json -InputObject $Policy -Depth 100 -Compress)) -EscapeForJson

            # A token CIPP knows resolves to a value, or to empty when its source is unset. One left
            # standing is a token nothing defines - usually a typo, or a custom variable that exists
            # on the tenant the template was written for and not on this one.
            #
            # Except that %name% is also Windows' own syntax for an environment variable, and Intune
            # policies are full of paths that use it. Those are meant to reach the device unexpanded
            # and are not CIPP's to resolve, so flagging them would report a problem on templates
            # that are entirely correct - which is how a warning gets learned and then ignored.
            $EnvironmentTokens = @(
                '%programfiles%', '%programfiles(x86)%', '%programdata%', '%windir%', '%systemroot%',
                '%systemdrive%', '%appdata%', '%localappdata%', '%temp%', '%tmp%', '%userprofile%',
                '%allusersprofile%', '%public%', '%computername%', '%username%', '%homedrive%',
                '%homepath%', '%path%', '%commonprogramfiles%', '%commonprogramfiles(x86)%'
            )
            $Unresolved = [regex]::Matches($Replaced, '%[A-Za-z0-9_.()-]+%') |
                ForEach-Object { $_.Value } |
                Where-Object { $_.ToLowerInvariant() -notin $EnvironmentTokens } |
                Sort-Object -Unique
            if ($Unresolved) {
                & $Add 'Warning' 'UnresolvedVariable' '' "These replacement variables do not resolve for $TenantFilter and would deploy literally: $($Unresolved -join ', ')."
            }
        } catch {
            & $Add 'Warning' 'ReplacementCheckFailed' '' "The replacement variables could not be checked for $TenantFilter : $($_.Exception.Message)"
        }

        if ($ResolvedType -eq 'Catalog' -and $Policy.templateReference.templateId) {
            try {
                # Endpoint Security templates expose different settings per tenant. Deployment drops
                # the ones the tenant does not offer, so the policy that lands is a subset - worth
                # saying out loud before someone compares the two and calls it drift.
                $Before = @($Policy.settings).Count
                $Filtered = Select-CIPPIntuneAvailableSetting -Policy ($Policy | ConvertTo-Json -Depth 100 -Compress | ConvertFrom-Json -Depth 100) -TenantFilter $TenantFilter
                $After = @($Filtered.settings).Count
                if ($After -lt $Before) {
                    & $Add 'Warning' 'SettingsUnavailable' 'settings' "$($Before - $After) of $Before settings are not offered by $TenantFilter and would be dropped on deployment."
                }
                if ($After -eq 0 -and $Before -gt 0) {
                    & $Add 'Error' 'NoSettingsAvailable' 'settings' "None of this template's $Before settings are offered by $TenantFilter, so deployment would create an empty policy."
                }
            } catch {
                & $Add 'Warning' 'AvailabilityCheckFailed' 'settings' "Setting availability could not be checked against $TenantFilter : $($_.Exception.Message)"
            }
        }
    }

    $ErrorMessages = @($Findings | Where-Object { $_.Severity -eq 'Error' } | ForEach-Object { $_.Message })

    return [pscustomobject]@{
        IsValid     = ($ErrorMessages.Count -eq 0)
        Type        = $ResolvedType
        DisplayName = $ResolvedName
        Findings    = @($Findings)
        Errors      = $ErrorMessages
        Warnings    = @($Findings | Where-Object { $_.Severity -eq 'Warning' } | ForEach-Object { $_.Message })
    }
}
