function Push-CIPPTestsList {
    <#
    .SYNOPSIS
        Build the list of test suite activities for a single tenant (Phase 1)

    .DESCRIPTION
        Checks whether the tenant has cached data and returns the test tasks for the tenant.
        Tasks are executed by Push-CIPPTestCollection, which runs the C# engine (path-independent,
        ModuleBuilder compatible) plus any leftover PS tests.

        All C#-engine suites are grouped into a SINGLE task so they run under one TenantData —
        each reporting type (Users, CAPolicies, …) is read and parsed once for the whole tenant
        instead of once per suite. The PS-only 'Custom' suite is emitted as its own task. This
        reduces the per-tenant activity count from ~262 (one per test) to 2 (engine group + Custom),
        cutting both orchestrator replay overhead and redundant per-suite data loads.

    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $TenantFilter = $Item.TenantFilter

    try {
        Write-Information "Building test suite list for tenant: $TenantFilter"

        # The orchestrator (Start-CIPPDBTestsRun) already filtered the tenant list to those
        # with cached data, so the previous per-tenant `Get-CIPPDbItem -CountsOnly` recheck
        # was a redundant Table query (one extra round-trip per tenant). The orchestrator
        # may pass SkipDbCheck=$true when it has already verified data presence; otherwise
        # we fall back to a check here for any direct invocations.
        if (-not $Item.SkipDbCheck) {
            $DbCounts = Get-CIPPDbItem -TenantFilter $TenantFilter -CountsOnly
            if (($DbCounts | Measure-Object -Property DataCount -Sum).Sum -eq 0) {
                Write-Information "Tenant $TenantFilter has no data in database. Skipping tests."
                return @()
            }
        }

        # Suite names must match the ValidateSet in Invoke-CIPPTestCollection.
        $EngineSuites = @('ZTNA', 'ORCA', 'EIDSCA', 'CISA', 'CIS', 'SMB1001', 'CopilotReadiness', 'GenericTests', 'E8')
        $AllSuites = @($EngineSuites) + 'Custom'

        # Optional caller-supplied suite filter (e.g. a Custom-only run). When present, restrict
        # the emitted suites to the requested subset so we don't spin up every suite unnecessarily.
        if ($Item.Suites) {
            $Requested = @($Item.Suites)
            $AllSuites = @($AllSuites | Where-Object { $_ -in $Requested })
            if ($AllSuites.Count -eq 0) {
                Write-Information "No suites matched the requested filter ($($Requested -join ', ')) for tenant $TenantFilter. Skipping."
                return @()
            }
            Write-Information "Suite filter applied for $TenantFilter — running: $($AllSuites -join ', ')"
        }

        $RunCustom = 'Custom' -in $AllSuites
        $FilteredEngine = @($AllSuites | Where-Object { $_ -ne 'Custom' })

        # Grouping mode. Default 'grouped': all C# suites run in ONE engine activity (one TenantData,
        # each reporting type read/parsed once) — fewer activities, no redundant data loads. Each
        # orchestrator activity is time-boxed (Function Apps: 10 min; Craft: 20 min), so the phases
        # are emitted as SEPARATE tasks (Engine / LeftoverPS / Custom) — each gets its own budget and
        # they fan out in parallel. If the grouped engine activity is ever too slow for a Function
        # App tenant, set CIPPTestsEngineGrouping=perSuite to fall back to the old per-suite fan-out
        # (one activity per suite, restoring cross-suite parallelism at the cost of re-reading shared
        # data per suite).
        $GroupingMode = if ([string]::IsNullOrWhiteSpace($env:CIPPTestsEngineGrouping)) { 'grouped' } else { $env:CIPPTestsEngineGrouping }

        $Tasks = [System.Collections.Generic.List[object]]::new()

        if ($FilteredEngine.Count -gt 0) {
            if ($GroupingMode -eq 'perSuite') {
                # Backwards-compatible fan-out: one activity per suite (engine + its leftover PS).
                foreach ($Suite in $FilteredEngine) {
                    $Tasks.Add([PSCustomObject]@{
                            FunctionName = 'CIPPTestCollection'
                            TenantFilter = $TenantFilter
                            SuiteName    = @($Suite)
                            Phase        = 'All'
                        })
                }
            } else {
                # Grouped: one engine activity for all C# suites (shared TenantData) ...
                $Tasks.Add([PSCustomObject]@{
                        FunctionName = 'CIPPTestCollection'
                        TenantFilter = $TenantFilter
                        SuiteName    = @($FilteredEngine)
                        Phase        = 'Engine'
                    })
                # ... and a SEPARATE activity for the remaining unported PS tests, only if any exist
                # on disk (avoids a no-op activity per tenant). Discovery is via Get-Command.
                $SuitePatterns = Get-CippTestSuitePatterns
                $HasLeftover = $false
                foreach ($Suite in $FilteredEngine) {
                    $Pattern = $SuitePatterns[$Suite]
                    if ($Pattern -and @(Get-Command -Name $Pattern -Module CIPPTests -ErrorAction SilentlyContinue).Count -gt 0) {
                        $HasLeftover = $true
                        break
                    }
                }
                if ($HasLeftover) {
                    $Tasks.Add([PSCustomObject]@{
                            FunctionName = 'CIPPTestCollection'
                            TenantFilter = $TenantFilter
                            SuiteName    = @($FilteredEngine)
                            Phase        = 'LeftoverPS'
                        })
                }
            }
        }

        if ($RunCustom) {
            $Tasks.Add([PSCustomObject]@{
                    FunctionName = 'CIPPTestCollection'
                    TenantFilter = $TenantFilter
                    SuiteName    = 'Custom'
                    Phase        = 'Custom'
                })
        }

        Write-Information "Built $($Tasks.Count) test task(s) for tenant $TenantFilter (grouping=$GroupingMode)"
        return @($Tasks)

    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "Failed to build test suite list: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return @()
    }
}
