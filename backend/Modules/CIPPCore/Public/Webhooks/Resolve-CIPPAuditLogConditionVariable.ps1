function Resolve-CIPPAuditLogConditionVariable {
    <#
    .SYNOPSIS
        An audit log rule's conditions with %variables% in their values replaced for one tenant, or nothing when a value
        names a variable the tenant has no value for.
    .DESCRIPTION
        Values take the tenant's custom variables and CIPP's own (%defaultdomain%, %tenantid%...) through
        Get-CIPPTextReplacement. For In and Not In, a value that held a variable is split on commas, so one variable can
        list several accounts. A rule with a variable the tenant does not define returns nothing, so it is not checked for
        that tenant rather than compared against the variable's name; so does one whose variable breaks the limits
        Invoke-AddAlert puts on typed values (500 values, 1,024 characters).
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        $Conditions
    )

    $Token = [regex]'%[A-Za-z][A-Za-z0-9_]*%'
    $Resolved = [System.Collections.Generic.List[object]]::new()
    foreach ($Condition in @($Conditions)) {
        $Values = @($Condition.Input.value)
        if ($Values.Where({ $Token.IsMatch([string]$_) }, 'First').Count -eq 0) { $Resolved.Add($Condition); continue }
        $List = ([string]$Condition.Operator.value).ToLowerInvariant() -in 'in', 'notin'
        $New = [System.Collections.Generic.List[string]]::new()
        foreach ($Value in $Values) {
            if (-not $Token.IsMatch([string]$Value)) { $New.Add([string]$Value); continue }
            $Text = [string](Get-CIPPTextReplacement -TenantFilter $TenantFilter -Text ([string]$Value))
            if ($Token.IsMatch($Text)) {
                Write-Warning "Audit log alert value '$Value' names a variable $TenantFilter has no value for; the alert is not checked for this tenant."
                return
            }
            if ($List) { foreach ($Part in $Text -split ',') { if ($Part.Trim()) { $New.Add($Part.Trim()) } } } else { $New.Add($Text) }
        }
        if ($New.Count -gt 500 -or $New.Where({ $_.Length -gt 1024 }, 'First').Count -gt 0) {
            Write-Warning "An audit log alert variable for $TenantFilter gives more than 500 values or a value over 1,024 characters; the alert is not checked for this tenant."
            return
        }
        $Copy = $Condition | Select-Object -Property *
        $Copy.Input = if ($List) { @(foreach ($Value in $New) { [pscustomobject]@{ value = $Value; label = $Value } }) } else { [pscustomobject]@{ value = $New[0]; label = $New[0] } }
        $Resolved.Add($Copy)
    }
    $Resolved.ToArray()
}
