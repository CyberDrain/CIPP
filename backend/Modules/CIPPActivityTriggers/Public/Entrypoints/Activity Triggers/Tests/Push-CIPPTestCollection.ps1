function Push-CIPPTestCollection {
    <#
    .SYNOPSIS
        Activity trigger: run all tests for a named suite against a tenant

    .DESCRIPTION
        Grouped test execution activity — the test-suite equivalent of the grouped
        CollectionType mode in Push-ExecCIPPDBCache. Delegates to Invoke-CIPPTestCollection
        which discovers and runs all matching Invoke-CippTest* functions via Get-Command
        (path-independent, ModuleBuilder compatible).

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    # SuiteName arrives as a SCALAR string on the wire — either a single suite ('Custom') or a
    # comma-joined group of engine suites ('ZTNA,ORCA,...'). Split it back to an array. (A nested
    # array property does not survive Craft's batch serialization; a scalar string does.)
    # Push-CIPPTestsList appends a phase suffix (_engine / _ps) to the Engine and LeftoverPS
    # SuiteName so those two activities — which carry the identical suite list — get distinct Craft
    # job ids instead of colliding onto a '_2' suffix. Strip it before parsing; the real phase is in
    # $Item.Phase. No real suite name ends in '_engine' or '_ps', so this only removes the marker.
    $RawSuiteName = ([string]$Item.SuiteName) -replace '_(engine|ps)$', ''
    $SuiteName = @(($RawSuiteName -split ',') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    $SuiteLabel = ($SuiteName -join '+')
    # Phase selects which work this activity does (Engine / LeftoverPS / Custom / All). Default 'All'
    # for back-compat with any caller that queues a task without a Phase.
    $Phase = if ([string]::IsNullOrWhiteSpace($Item.Phase)) { 'All' } else { $Item.Phase }

    try {
        Write-Information "Running [$Phase] $SuiteLabel for tenant $TenantFilter"

        $Result = Invoke-CIPPTestCollection -SuiteName $SuiteName -TenantFilter $TenantFilter -Phase $Phase

        Write-Information "Completed [$Phase] $SuiteLabel for $TenantFilter - $($Result.Success)/$($Result.Total) tests ran in $($Result.TotalSeconds)s"
        return "Successfully executed [$Phase] $SuiteLabel for $TenantFilter ($($Result.Success)/$($Result.Total) ran, $($Result.Failed) errored)"

    } catch {
        $ErrorMsg = "Failed to execute [$Phase] $SuiteLabel for tenant $TenantFilter : $($_.Exception.Message)"
        Write-LogMessage -API 'Tests' -tenant $TenantFilter -message $ErrorMsg -sev Error
        throw $ErrorMsg
    }
}
