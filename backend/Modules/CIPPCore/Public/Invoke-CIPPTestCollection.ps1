function Invoke-CIPPTestCollection {
    <#
    .SYNOPSIS
        Execute a phase of one or more test suites against a tenant

    .DESCRIPTION
        Runs tests for the requested suite(s) against a tenant within a single activity invocation.
        Test execution is split into three independent PHASES so each runs as its own orchestrator
        activity with its own timeout budget (Function Apps cap an activity at 10 min; Craft at 20):

        - Engine     : the C# engine (CIPPSharp/TestEngine) for all requested non-Custom suites,
                       run together under ONE TenantData so each reporting type (Users, CAPolicies,
                       …) is read and parsed exactly once for the whole group instead of once per
                       suite. This is the bulk of every suite and the big data-sharing win.
        - LeftoverPS : the few tests not yet ported to C# (currently GenericTest010/011), discovered
                       on disk via Get-Command (path-independent, ModuleBuilder safe). Kept in its
                       own activity so its live work never eats into the engine activity's timeout.
        - Custom     : PS-only custom scripts. Invoke-CippTestCustomScripts requires a ScriptGuid,
                       so enabled ScriptGuids are enumerated from the DB and called once per guid.

        'All' (the default) runs every applicable phase in one activity — used for direct/manual
        invocations and the per-suite fallback fan-out.

        The suite-to-pattern map lives in Get-CippTestSuitePatterns (single source of truth, also
        used to label stored results with their suite).

    .PARAMETER SuiteName
        One or more suites to execute. Each must match a key in the internal suite map. Non-Custom
        suites are grouped into a single engine call; 'Custom' is handled by its PS-only path.

    .PARAMETER TenantFilter
        Tenant domain to run tests against.

    .PARAMETER Phase
        Which phase(s) to run: 'Engine', 'LeftoverPS', 'Custom', or 'All' (default). The orchestrator
        emits one task per phase per tenant so each gets an independent timeout budget.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ZTNA', 'ORCA', 'EIDSCA', 'CISA', 'CIS', 'SMB1001', 'CopilotReadiness', 'GenericTests', 'E8', 'Custom')]
        [string[]]$SuiteName,

        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,

        [Parameter(Mandatory = $false)]
        [ValidateSet('All', 'Engine', 'LeftoverPS', 'Custom')]
        [string]$Phase = 'All'
    )

    # Canonical suite-to-pattern map — single source of truth, shared with the suite labelling in
    # Get-CIPPTestResultsTenants. Discovery is done via Get-Command so this is path-independent
    # and ModuleBuilder safe.
    $SuitePatterns = Get-CippTestSuitePatterns

    $Suites = @($SuiteName)
    $RunCustomSuite = 'Custom' -in $Suites
    $EngineSuites = @($Suites | Where-Object { $_ -ne 'Custom' })
    $SuiteLabel = ($Suites -join '+')

    $DoEngine = ($Phase -in @('All', 'Engine')) -and $EngineSuites.Count -gt 0
    $DoLeftover = ($Phase -in @('All', 'LeftoverPS')) -and $EngineSuites.Count -gt 0
    $DoCustom = ($Phase -in @('All', 'Custom')) -and $RunCustomSuite

    $SuiteStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $SuccessCount = 0
    $FailedCount = 0
    $EngineRan = 0
    $EngineFailed = 0
    $Errors = [System.Collections.Generic.List[string]]::new()
    $Timings = [System.Collections.Generic.List[string]]::new()

    # ── Engine phase: all requested C# suites in one grouped run (shared TenantData) ──
    if ($DoEngine) {
        try {
            $EngineSummary = Invoke-CIPPTestEngineRun -TenantFilter $TenantFilter -SuiteName $EngineSuites
            $EngineRan = [int]$EngineSummary.Ran
            $EngineFailed = [int]$EngineSummary.Failed
            $SuccessCount += $EngineRan
            $FailedCount += $EngineFailed
            $Timings.Add(('[engine] {0} : {1}s ({2} ran, {3} failed)' -f ($EngineSuites -join '+'), $EngineSummary.TotalSeconds, $EngineRan, $EngineFailed))
        } catch {
            # No registered C# tests for these suites, or a registry/engine problem: log so the run
            # still surfaces the issue. The LeftoverPS phase (separate activity) still runs.
            Write-Information "Engine run skipped for $($EngineSuites -join '+') / $TenantFilter : $($_.Exception.Message)"
        }
    }

    # ── LeftoverPS phase: remaining unported PS tests, per engine suite ──
    # No double-run: the engine covers exactly the registry's tests, this pass covers exactly what is
    # still on disk (different ids). Discovered via Get-Command so dropped/ported .ps1 never match.
    if ($DoLeftover) {
        $Table = Get-CippTable -tablename 'CippTestResults'
        $ResultBatch = [System.Collections.Generic.List[hashtable]]::new()

        foreach ($Suite in $EngineSuites) {
            $Pattern = $SuitePatterns[$Suite]
            if (-not $Pattern) { continue }
            $LeftoverFunctions = @(Get-Command -Name $Pattern -Module CIPPTests -ErrorAction SilentlyContinue)
            if ($LeftoverFunctions.Count -eq 0) { continue }

            Write-Information "Running $($LeftoverFunctions.Count) remaining PS test(s) for $Suite / $TenantFilter"
            foreach ($TestFunction in $LeftoverFunctions) {
                $ItemStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                try {
                    $TestOutput = @(& $TestFunction -Tenant $TenantFilter)
                    foreach ($Entity in $TestOutput) {
                        if ($Entity -is [hashtable] -and $Entity.PartitionKey) {
                            $ResultBatch.Add($Entity)
                        }
                    }
                    if ($ResultBatch.Count -ge 100) {
                        Add-CIPPAzDataTableEntity @Table -Entity @($ResultBatch) -Force
                        $ResultBatch.Clear()
                    }
                    $ItemStopwatch.Stop()
                    $Timings.Add(('{0} : {1:N3}s' -f $TestFunction.Name, $ItemStopwatch.Elapsed.TotalSeconds))
                    $SuccessCount++
                } catch {
                    $ItemStopwatch.Stop()
                    $FailedCount++
                    $Errors.Add("$($TestFunction.Name) : $($_.Exception.Message)")
                    $Timings.Add(('{0} : {1:N3}s (FAILED)' -f $TestFunction.Name, $ItemStopwatch.Elapsed.TotalSeconds))
                }
            }
        }

        if ($ResultBatch.Count -gt 0) {
            Add-CIPPAzDataTableEntity @Table -Entity @($ResultBatch) -Force
        }
    }

    # ── Custom phase: PS-only. One call per enabled ScriptGuid (latest version). ──
    if ($DoCustom) {
        if (-not (Get-Command -Name 'Invoke-CippTestCustomScripts' -ErrorAction SilentlyContinue)) {
            Write-Information 'Invoke-CippTestCustomScripts not found — skipping Custom suite'
        } else {
            $CustomTable = Get-CippTable -TableName 'CustomPowershellScripts'
            $AllScripts = @(Get-CIPPAzDataTableEntity @CustomTable -Filter "PartitionKey eq 'CustomScript'")

            # Single-pass "latest enabled version per ScriptGuid" (O(n), no per-guid Group/Sort).
            $LatestByGuid = @{}
            foreach ($Script in $AllScripts) {
                $Guid = $Script.ScriptGuid
                if (-not $Guid) { continue }
                $Existing = $LatestByGuid[$Guid]
                if (-not $Existing -or [int]$Script.Version -gt [int]$Existing.Version) {
                    $LatestByGuid[$Guid] = $Script
                }
            }

            $EnabledGuidsList = [System.Collections.Generic.List[string]]::new()
            foreach ($Latest in $LatestByGuid.Values) {
                $EnabledProp = $Latest.PSObject.Properties['Enabled']
                if (-not $EnabledProp -or [bool]$EnabledProp.Value) {
                    $EnabledGuidsList.Add($Latest.ScriptGuid)
                }
            }
            $EnabledGuids = $EnabledGuidsList.ToArray()

            if ($EnabledGuids.Count -eq 0) {
                Write-Information 'No enabled custom scripts found — skipping Custom suite'
            } else {
                Write-Information "Starting Custom suite for $TenantFilter ($($EnabledGuids.Count) scripts)"

                $Table = Get-CippTable -tablename 'CippTestResults'
                $ResultBatch = [System.Collections.Generic.List[hashtable]]::new()
                $AlertBatch = [System.Collections.Generic.List[object]]::new()

                foreach ($Guid in $EnabledGuids) {
                    $ItemStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
                    try {
                        Write-Information "  [Custom] Running CustomScript-$Guid for $TenantFilter"
                        $TestOutput = @(Invoke-CippTestCustomScripts -Tenant $TenantFilter -ScriptGuid $Guid)
                        foreach ($Entity in $TestOutput) {
                            if ($Entity -is [hashtable] -and $Entity.PartitionKey -and $Entity.RowKey) {
                                $ResultBatch.Add($Entity)
                            } elseif ($Entity -isnot [hashtable] -and $Entity.PSObject.Properties['CippCustomTestAlert']) {
                                $AlertBatch.Add($Entity)
                            }
                        }
                        if ($ResultBatch.Count -ge 100) {
                            Add-CIPPAzDataTableEntity @Table -Entity @($ResultBatch) -Force
                            Write-Information "  [Custom] Flushed $($ResultBatch.Count) results to table"
                            $ResultBatch.Clear()
                        }
                        $ItemStopwatch.Stop()
                        $ElapsedSeconds = '{0:N3}' -f $ItemStopwatch.Elapsed.TotalSeconds
                        $Timings.Add("CustomScript-$Guid : ${ElapsedSeconds}s")
                        Write-Information "  [Custom] Completed CustomScript-$Guid - ${ElapsedSeconds}s"
                        $SuccessCount++
                    } catch {
                        $ItemStopwatch.Stop()
                        $ElapsedSeconds = '{0:N3}' -f $ItemStopwatch.Elapsed.TotalSeconds
                        $FailedCount++
                        $Errors.Add("CustomScript-$Guid : $($_.Exception.Message)")
                        $Timings.Add("CustomScript-$Guid : ${ElapsedSeconds}s (FAILED)")
                        Write-Warning "  [Custom] Failed CustomScript-$Guid after ${ElapsedSeconds}s: $($_.Exception.Message)"
                    }
                }

                if ($ResultBatch.Count -gt 0) {
                    Add-CIPPAzDataTableEntity @Table -Entity @($ResultBatch) -Force
                    Write-Information "  [Custom] Flushed final $($ResultBatch.Count) results to table"
                }

                # Ship a single aggregated alert for the tenant covering all alert-worthy results.
                if ($AlertBatch.Count -gt 0) {
                    Write-Information "  [Custom] Shipping $($AlertBatch.Count) custom test alert(s) for $TenantFilter"
                    Send-CIPPCustomTestAlert -TenantFilter $TenantFilter -Alerts @($AlertBatch)
                }
            }
        }
    }

    $SuiteStopwatch.Stop()
    $TotalElapsed = '{0:N3}' -f $SuiteStopwatch.Elapsed.TotalSeconds
    $Total = $SuccessCount + $FailedCount
    $Summary = "[$Phase] $SuiteLabel for $TenantFilter completed in ${TotalElapsed}s — $SuccessCount ran, $FailedCount errored (engine: $EngineRan ran / $EngineFailed failed)"
    Write-Information $Summary
    Write-Information "  Timings: $($Timings -join ' | ')"

    if ($FailedCount -gt 0) {
        Write-LogMessage -API 'Tests' -tenant $TenantFilter -message "$Summary. Errors: $($Errors -join '; ')" -sev Warning
    }

    return @{
        SuiteName    = $SuiteLabel
        Phase        = $Phase
        TenantFilter = $TenantFilter
        Success      = $SuccessCount
        Failed       = $FailedCount
        Total        = $Total
        TotalSeconds = $TotalElapsed
        Timings      = @($Timings)
        Errors       = @($Errors)
    }
}
