function Get-CippSandboxData {
    <#
    .SYNOPSIS
        Pre-fetches the tenant-locked cache data a custom test requests.

    .DESCRIPTION
        Runs on the trusted (FullLanguage) side before the script enters the sandbox.
        Inspects the script AST for Get-CIPPTestData calls, resolves each requested -Type,
        and fetches that data for the supplied tenant via the real Get-CIPPTestData. The
        result is a hashtable keyed by Type that the sandbox proxy serves.

        Because only the requested types for THIS tenant are fetched and injected, the
        sandbox is structurally unable to read any other tenant's data.

        -Type must be a string literal. Dynamic type names cannot be pre-fetched and are
        rejected with a clear error (rather than silently returning empty data).

    .PARAMETER ScriptContent
        The (already text-replaced, already validated) script content.

    .PARAMETER TenantFilter
        The tenant to fetch data for.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptContent,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter
    )

    $Ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptContent, [ref]$null, [ref]$null)

    $Calls = $Ast.FindAll({
            param($Node)
            $Node -is [System.Management.Automation.Language.CommandAst] -and
            $Node.GetCommandName() -eq 'Get-CIPPTestData'
        }, $true)

    $Data = @{}
    # Per-type union of the fields a script asked for, and the set of types that must load whole
    # because at least one call did not declare literal -Fields (or asked to skip projection).
    $FieldsByType = @{}
    $FullTypes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    function Resolve-CallValue($Element, $Call, $Index) {
        if ($Element.Argument) { return $Element.Argument }
        if ($Index + 1 -lt $Call.CommandElements.Count) { return $Call.CommandElements[$Index + 1] }
        return $null
    }

    foreach ($Call in $Calls) {
        $Type = $null
        $HasType = $false
        $TypeIsLiteral = $true
        $CallFields = [System.Collections.Generic.List[string]]::new()
        $HasFields = $false
        $FieldsLiteral = $true

        for ($i = 0; $i -lt $Call.CommandElements.Count; $i++) {
            $Element = $Call.CommandElements[$i]
            if ($Element -isnot [System.Management.Automation.Language.CommandParameterAst]) { continue }

            if ($Element.ParameterName -ieq 'Type') {
                $HasType = $true
                $Value = Resolve-CallValue $Element $Call $i
                if ($Value -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $Type = $Value.Value }
                else { $TypeIsLiteral = $false }
            } elseif ($Element.ParameterName -ieq 'Fields') {
                $HasFields = $true
                $Value = Resolve-CallValue $Element $Call $i
                if ($Value -is [System.Management.Automation.Language.ArrayLiteralAst]) {
                    foreach ($El in $Value.Elements) {
                        if ($El -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $CallFields.Add($El.Value) }
                        else { $FieldsLiteral = $false }
                    }
                } elseif ($Value -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $CallFields.Add($Value.Value)
                } else {
                    $FieldsLiteral = $false # dynamic/computed field list -> cannot project safely
                }
            } elseif ($Element.ParameterName -ieq 'NoProjection') {
                $FieldsLiteral = $false # explicit whole-record request
            }
        }

        if ($HasType -and -not $TypeIsLiteral) {
            throw "Custom test sandbox requires a literal -Type for Get-CIPPTestData (for example: Get-CIPPTestData -Type 'Users'). Dynamic or computed type names are not supported."
        }

        $Key = if ($Type) { $Type } else { '' }
        # A type is projected only if EVERY call for it declared literal fields; any call without them
        # (or with -NoProjection / a dynamic list) forces the whole record — the safe default.
        if (-not $HasFields -or -not $FieldsLiteral) {
            [void]$FullTypes.Add($Key)
        } else {
            if (-not $FieldsByType.ContainsKey($Key)) {
                $FieldsByType[$Key] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            }
            foreach ($F in $CallFields) { [void]$FieldsByType[$Key].Add($F) }
        }
    }

    $Keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $FieldsByType.Keys) { [void]$Keys.Add($k) }
    foreach ($k in $FullTypes) { [void]$Keys.Add($k) }

    foreach ($Key in $Keys) {
        if ($FullTypes.Contains($Key) -or -not $FieldsByType.ContainsKey($Key)) {
            $Data[$Key] = @(Get-CIPPTestData -TenantFilter $TenantFilter -Type $Key -NoProjection)
        } else {
            $Fields = @($FieldsByType[$Key])
            $Data[$Key] = @(Get-CIPPTestData -TenantFilter $TenantFilter -Type $Key -Fields $Fields)
        }
    }

    return $Data
}
