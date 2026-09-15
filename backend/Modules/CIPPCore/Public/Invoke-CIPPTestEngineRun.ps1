function Invoke-CIPPTestEngineRun {
    <#
    .SYNOPSIS
        PowerShell dispatch shim for the C# test engine (CIPPSharp / CIPP.Tests.TestEngine).

    .DESCRIPTION
        The C# engine is deliberately minimal: given a partition key it looks the cached data up by
        that key, runs the suite's tests, writes the results to CippTestResults, and hands a summary
        back. It does NO tenant resolution. This shim owns that resolution:

        CippReportingDB is partitioned by defaultDomainName (Add-CIPPDbItem resolves GUIDs/customerIds
        to defaultDomainName on write), so a raw GUID/customerId handed to the engine would read an
        empty partition and every test would Skip. We resolve to defaultDomainName here, in PS,
        before calling C#.

        Logging is bridged with CIPP.Tests.DelegateLogSink (delegates), NOT a PowerShell class that
        implements ILogSink — a PS `class : <C# interface>` fails ModuleBuilder's parse-time type
        resolution and would drop this whole file from the function-parameter cache.

    .PARAMETER TenantFilter
        Tenant domain, GUID, or customerId to run the suite against.

    .PARAMETER SuiteName
        One or more suites to run (each must exist in tests.registry.json), e.g. 'CopilotReadiness'
        or @('CIS','CISA','E8',...). When several are passed they run under a SINGLE TenantData: each
        reporting type (Users, CAPolicies, …) is read from the table and parsed exactly once for the
        whole group instead of once per suite. A suite with no registered C# tests is skipped by the
        engine (its leftover .ps1 run separately).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantFilter,

        [Parameter(Mandatory)]
        [string[]]$SuiteName
    )

    # Resolve the partition key HERE (the engine does not). Fall back to the raw value so a caller
    # that already passes a defaultDomainName still works.
    $Tenant = (Get-Tenants -TenantFilter $TenantFilter).defaultDomainName
    if ([string]::IsNullOrWhiteSpace($Tenant)) { $Tenant = $TenantFilter }

    # Point the engine at tests.registry.json deterministically. Left to itself it probes relative
    # paths, which differ between the repo (backend/Modules/...) and the runtime container (backend
    # is mounted at /app/API, so Modules/... has no backend/ prefix). $env:CIPPRootPath is the app
    # root the other test endpoints use.
    if ([string]::IsNullOrWhiteSpace($env:CIPP_TESTS_REGISTRY) -and -not [string]::IsNullOrWhiteSpace($env:CIPPRootPath)) {
        $RegistryPath = Join-Path $env:CIPPRootPath 'Modules/CIPPTests/tests.registry.json'
        if (Test-Path $RegistryPath) { $env:CIPP_TESTS_REGISTRY = $RegistryPath }
    }

    $Client = [CIPP.Tests.CippTableClient]::new()

    # ILogSink via delegates: Info -> craft.log (Write-Information); Warn/Error -> audit log
    # (Write-LogMessage). $Tenant is captured for the suite-level log lines the engine emits with a
    # null tenant. Constructed at runtime, so no parse-time interface dependency.
    $InfoCb = [Action[string, string, string]] { param($Message, $LogTenant, $TestId) Write-Information $Message }
    $WarnCb = [Action[string, string, string]] {
        param($Message, $LogTenant, $TestId)
        $T = if ([string]::IsNullOrWhiteSpace($LogTenant)) { $Tenant } else { $LogTenant }
        Write-LogMessage -API 'Tests' -tenant $T -message $Message -sev Warning
    }
    $ErrorCb = [Action[string, string, string, Exception]] {
        param($Message, $LogTenant, $TestId, $Ex)
        $T = if ([string]::IsNullOrWhiteSpace($LogTenant)) { $Tenant } else { $LogTenant }
        $Full = if ($Ex) { "$Message : $($Ex.Message)" } else { $Message }
        Write-LogMessage -API 'Tests' -tenant $T -message $Full -sev Error
    }
    $Log = [CIPP.Tests.DelegateLogSink]::new($InfoCb, $WarnCb, $ErrorCb)

    # Resolve tenant capabilities ONCE here (the engine does no live license work). The engine gates
    # each test against the registry's requiredCapabilities using this map, emitting Unlicensed for
    # those the tenant can't run — the license preflight, done once per tenant instead of per test.
    $Capabilities = [System.Collections.Generic.Dictionary[string, bool]]::new([System.StringComparer]::OrdinalIgnoreCase)
    try {
        $Caps = Get-CIPPTenantCapabilities -TenantFilter $Tenant
        if ($Caps) {
            foreach ($Prop in $Caps.PSObject.Properties) {
                $Capabilities[$Prop.Name] = [bool]$Prop.Value
            }
        }
    } catch {
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "Could not resolve tenant capabilities; license gating disabled for this run: $($_.Exception.Message)" -sev Warning
    }

    $SuiteLabel = ($SuiteName -join '+')
    try {
        # RunSuites: all requested suites under one TenantData (one read+parse of each type total).
        $Summary = [CIPP.Tests.TestEngine]::RunSuites($Tenant, [string[]]$SuiteName, $Client, $Log, $Capabilities)
        Write-Information "TestEngine $SuiteLabel for $($Tenant): $($Summary.Ran) ran, $($Summary.Failed) failed, $($Summary.TotalSeconds)s"
        return $Summary
    } catch {
        Write-LogMessage -API 'Tests' -tenant $Tenant -message "TestEngine $SuiteLabel failed: $($_.Exception.Message)" -sev Error
        throw
    }
}
