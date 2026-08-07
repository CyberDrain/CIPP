function Get-CIPPIntuneTemplateType {
    <#
    .SYNOPSIS
        Resolves the policy type of a stored Intune template.

    .DESCRIPTION
        Returns the template's recorded Type when it has one. Templates imported before Type was
        stored have none, so the type is inferred from the shape of the raw policy payload instead.
        Returns $null when the type is neither recorded nor inferable, which means the template
        needs re-importing.

    .PARAMETER Type
        The template's recorded Type, if any.

    .PARAMETER RawJson
        The policy to infer from when Type is empty, as a JSON string or an already parsed object.
        Callers hold it both ways - stored templates keep it as a string, the import path has already
        parsed it - and passing an object used to infer nothing rather than fail, which reads as a
        template with no determinable type.

    .EXAMPLE
        Get-CIPPIntuneTemplateType -Type $Template.Type -RawJson $Template.RAWJson
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [string]$Type,
        $RawJson
    )

    if ($Type) {
        return $Type
    }

    try {
        $ParsedRaw = if ($RawJson -is [string]) {
            $RawJson | ConvertFrom-Json -ErrorAction SilentlyContinue
        } else {
            $RawJson
        }
        $ODataType = $ParsedRaw.'@odata.type'

        if ($null -ne $ParsedRaw.settings -and $null -ne $ParsedRaw.technologies) { return 'Catalog' }
        if ($null -ne $ParsedRaw.scheduledActionsForRule -or $ODataType -match 'CompliancePolicy') { return 'deviceCompliancePolicies' }
        if ($ODataType -match 'windowsDriverUpdateProfile') { return 'windowsDriverUpdateProfiles' }
        if ($ODataType -match 'ManagedApp|managedAppProtection') { return 'AppProtection' }
        if ($ODataType -match 'deviceConfiguration|#microsoft\.graph\.\w+Configuration$') { return 'Device' }
    } catch {
        return $null
    }

    return $null
}
