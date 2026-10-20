function Get-HuduUiHumanized {
    <#
        .SYNOPSIS
        Turns a camelCase API value into sentence case, for example noncompliant or inGracePeriod.
    #>
    param([string]$Text)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $Spaced = ($Text -creplace '(?<=[a-z0-9])(?=[A-Z])', ' ').Trim()
    $Spaced.Substring(0, 1).ToUpper() + $Spaced.Substring(1).ToLower()
}
