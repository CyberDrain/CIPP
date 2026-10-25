function Test-CIPPConditionFilter {
    <#
    .SYNOPSIS
        Returns a sanitized PowerShell condition string for an audit log / delta query condition.
    .DESCRIPTION
        Validates operator and property name against allowlists, sanitizes input values,
        then returns a safe condition string suitable for [ScriptBlock]::Create().

        This replaces the old Invoke-Expression pattern which was vulnerable to code injection
        through unsanitized user-controlled fields.
    .PARAMETER Condition
        A single condition object with Property.label, Operator.value, and Input.value.
    .OUTPUTS
        [string] A sanitized PowerShell condition string, or $null if validation fails.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        $Condition
    )

    # Operator allowlist - only these PowerShell comparison operators are permitted
    $AllowedOperators = @(
        'eq', 'ne', 'like', 'notlike', 'match', 'notmatch',
        'gt', 'lt', 'ge', 'le', 'in', 'notin',
        'contains', 'notcontains', 'between', 'notbetween'
    )

    # Property name validation - only alphanumeric, underscores, and dots allowed
    $SafePropertyRegex = [regex]'^[a-zA-Z0-9_.]+$'

    # Value sanitization - block characters that enable code injection
    $UnsafeValueRegex = [regex]'[;|`\$\{\}]'

    $propertyName = $Condition.Property.label
    $operatorValue = $Condition.Operator.value.ToLower()
    $inputValue = $Condition.Input.value

    # Validate operator against allowlist
    if ($operatorValue -notin $AllowedOperators) {
        Write-Warning "Blocked invalid operator '$($Condition.Operator.value)' in condition for property '$propertyName'"
        return $null
    }

    # Validate property name to prevent injection via property paths
    if (-not $SafePropertyRegex.IsMatch($propertyName)) {
        Write-Warning "Blocked invalid property name '$propertyName' in condition"
        return $null
    }

    # A time of day window, HH:mm-HH:mm; one that crosses midnight holds the times after its start or before its end.
    if ($operatorValue -in 'between', 'notbetween') {
        if ([string]$inputValue -notmatch '^((?:[01]\d|2[0-3]):[0-5]\d)-((?:[01]\d|2[0-3]):[0-5]\d)$') {
            Write-Warning "Blocked invalid time window '$inputValue' for property '$propertyName'"
            return $null
        }
        $Join = if ($Matches[1] -le $Matches[2]) { 'and' } else { 'or' }
        $Window = "(`$_.$propertyName -ge '$($Matches[1])' -$Join `$_.$propertyName -lt '$($Matches[2])')"
        return $(if ($operatorValue -eq 'between') { $Window } else { "(`$_.$propertyName -and -not $Window)" })
    }

    # Build sanitized condition string
    if ($inputValue -is [array]) {
        # Sanitize each array element
        $sanitizedItems = foreach ($item in $inputValue) {
            $itemStr = [string]$item
            if ($UnsafeValueRegex.IsMatch($itemStr)) {
                Write-Warning "Blocked unsafe value in array for property '$propertyName': '$itemStr'"
                return $null
            }
            $itemStr -replace "'", "''"
        }
        if ($null -eq $sanitizedItems) { return $null }
        $arrayAsString = $sanitizedItems | ForEach-Object { "'$_'" }
        $value = "@($($arrayAsString -join ', '))"
    } else {
        $valueStr = [string]$inputValue
        if ($UnsafeValueRegex.IsMatch($valueStr)) {
            Write-Warning "Blocked unsafe value for property '$propertyName': '$valueStr'"
            return $null
        }
        $value = "'$($valueStr -replace "'", "''")'"
    }

    # A regex runs without backtracking, in time linear in the value, so a crafted value (a sign-in's user agent) cannot
    # hold the worker; the cache keeps every rule's pattern built, and the time limit is only a backstop.
    if ($operatorValue -in 'match', 'notmatch') {
        if ([regex]::CacheSize -lt 256) { [regex]::CacheSize = 256 }
        $Not = if ($operatorValue -eq 'notmatch') { '-not ' } else { '' }
        return "`$(try { $Not[regex]::IsMatch([string]`$(`$_.$propertyName), $value, 'IgnoreCase, NonBacktracking', [timespan]::FromMilliseconds(50)) } catch { `$false })"
    }

    return "`$(`$_.$propertyName) -$operatorValue $value"
}
