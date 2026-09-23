#Requires -Version 7.4
<#
.SYNOPSIS
    Simulates several API clients with different appetites against the local dev stack so the
    self-diagnostics timer, checks and per-client log view have realistic data to show.

.DESCRIPTION
    Each simulated client runs in its own worker at its own target rate, picking endpoints at
    random from a weighted mix (mostly cheap GetVersion calls, some heavier Graph-backed lists).
    Requests carry the header trio Craft needs to route them down the API-client branch of
    Test-CIPPAccess: x-ms-client-principal-idp, x-ms-client-principal-name (the AppId) and a
    base64 x-ms-client-principal (without it the dev DevRoles principal replaces the caller).

    Rate limits are respected: a 429 is not counted as usage, the worker sleeps for Retry-After
    (or a backoff) and only then resumes, so the recorded usage matches what the instance
    actually served.

    Clients must exist in the ApiClients table. -Register seeds them (needs a dev session:
    dot-source build/tools/Initialize-DevEnvironment.ps1 first).

.PARAMETER DurationHours
    How long to keep sending. Fractional values are fine (0.25 = 15 minutes).
.PARAMETER RateScale
    Multiplier on every client's built-in requests-per-minute target.
.PARAMETER TenantFilter
    Tenant used for the Graph-backed endpoints. Read-only calls only.
.PARAMETER Register
    Seed the ApiClients rows before starting.
.PARAMETER Burst
    Send roughly this many requests as fast as the instance allows, then exit. For quick checks.

.EXAMPLE
    . ./build/tools/Initialize-DevEnvironment.ps1
    ./build/tools/Start-ApiClientLoadTest.ps1 -Register -DurationHours 3
.EXAMPLE
    ./build/tools/Start-ApiClientLoadTest.ps1 -Burst 500
#>
[CmdletBinding()]
param(
    [ValidateRange(0.01, 72)][double]$DurationHours = 1,
    [ValidateRange(0.1, 20)][double]$RateScale = 1,
    [string]$TenantFilter = '7ngn50.onmicrosoft.com',
    [string]$BaseUrl = 'http://localhost:5196',
    [switch]$Register,
    [ValidateRange(0, 100000)][int]$Burst = 0
)

# Fixed GUIDs so repeated runs aggregate under the same clients. Rates are requests per minute;
# the spread is deliberate so one integration visibly dominates the api-clients check.
$Clients = @(
    @{ AppId = 'b0a0a0a0-1111-4222-8333-c0ffee000001'; AppName = 'LoadTest Integration'; IP = '203.0.113.42'; Rpm = 40 }
    @{ AppId = 'b0a0a0a0-1111-4222-8333-c0ffee000002'; AppName = 'Rewst Automation'; IP = '198.51.100.7'; Rpm = 12 }
    @{ AppId = 'b0a0a0a0-1111-4222-8333-c0ffee000003'; AppName = 'Hudu Sync'; IP = '198.51.100.23'; Rpm = 4 }
    @{ AppId = 'b0a0a0a0-1111-4222-8333-c0ffee000004'; AppName = 'Reporting Script'; IP = '192.0.2.88'; Rpm = 1 }
)

# Weighted endpoint mix. GetVersion is the cheap filler; the rest hit Graph for the tenant.
$Endpoints = @(
    @{ Path = 'GetVersion'; Weight = 50 }
    @{ Path = "ListUsers?tenantFilter=$TenantFilter"; Weight = 20 }
    @{ Path = "ListGroups?tenantFilter=$TenantFilter"; Weight = 15 }
    @{ Path = "ListSignIns?tenantFilter=$TenantFilter&Days=1"; Weight = 10 }
    @{ Path = "ListMailboxes?tenantFilter=$TenantFilter"; Weight = 5 }
)

if ($Register) {
    if (-not (Get-Command Get-CIPPTable -ErrorAction SilentlyContinue)) {
        throw 'Dot-source build/tools/Initialize-DevEnvironment.ps1 before using -Register.'
    }
    $Table = Get-CIPPTable -TableName 'ApiClients'
    foreach ($c in $Clients) {
        Add-CIPPAzDataTableEntity @Table -Force -Entity @{
            PartitionKey = 'ApiClients'
            RowKey       = $c.AppId
            AppName      = $c.AppName
            Role         = 'readonly'
            IPRange      = '["Any"]'
            Enabled      = $true
            MCPAllowed   = $false
        } | Out-Null
        Write-Host "Registered API client $($c.AppName) ($($c.AppId))" -ForegroundColor Green
    }
}

# Headers are built up front so the parallel workers stay free of helper functions.
foreach ($c in $Clients) {
    $Principal = @{
        identityProvider = 'aad'
        userId           = $c.AppId
        userDetails      = $c.AppName
        userRoles        = @('authenticated')
        claims           = @(@{ typ = 'azp'; val = $c.AppId })
    } | ConvertTo-Json -Compress
    $c.Headers = @{
        'x-ms-client-principal-idp'  = 'aad'
        'x-ms-client-principal-name' = $c.AppId
        'x-ms-client-principal'      = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Principal))
        'x-forwarded-for'            = $c.IP
    }
    # Prove each identity lands on the API-client branch before starting a long run.
    $Probe = Invoke-WebRequest -Uri "$BaseUrl/api/GetVersion" -Headers $c.Headers -TimeoutSec 30 -SkipHttpErrorCheck -NoProxy
    if ($Probe.StatusCode -ne 200) {
        throw "Dev backend returned $($Probe.StatusCode) for $($c.AppName). Is $($c.AppId) in the ApiClients table? Use -Register."
    }
}

$Deadline = if ($Burst -gt 0) { [DateTime]::MaxValue } else { [DateTime]::UtcNow.AddHours($DurationHours) }
$TotalWeight = ($Endpoints | Measure-Object -Property Weight -Sum).Sum
$PerClientBurst = [math]::Ceiling($Burst / $Clients.Count)
Write-Host "Starting $($Clients.Count) client(s) against $BaseUrl until $($Deadline.ToString('u')) (rate x$RateScale)$(if ($Burst) { " - burst of $Burst" })" -ForegroundColor Cyan

$Results = $Clients | ForEach-Object -ThrottleLimit $Clients.Count -Parallel {
    $c = $_
    $endpoints = $using:Endpoints
    $totalWeight = $using:TotalWeight
    $baseUrl = $using:BaseUrl
    $deadline = $using:Deadline
    $burstTarget = $using:PerClientBurst
    $rpm = $c.Rpm * $using:RateScale
    $intervalMs = if ($burstTarget) { 0 } else { [int](60000 / $rpm) }
    $rng = [System.Random]::new()
    $codes = @{}
    $sent = 0

    while ([DateTime]::UtcNow -lt $deadline -and ($burstTarget -eq 0 -or $sent -lt $burstTarget)) {
        # Weighted random endpoint.
        $roll = $rng.Next($totalWeight)
        $acc = 0
        $pick = $endpoints[-1]
        foreach ($e in $endpoints) { $acc += $e.Weight; if ($roll -lt $acc) { $pick = $e; break } }

        try {
            # -NoProxy: a system proxy (e.g. Proxyman) silently drops most of a parallel burst.
            $r = Invoke-WebRequest -Uri "$baseUrl/api/$($pick.Path)" -Headers $c.Headers -TimeoutSec 300 -SkipHttpErrorCheck -NoProxy -ErrorAction Stop
            $code = [string]$r.StatusCode
            $codes[$code] = 1 + [int]$codes[$code]
            if ($r.StatusCode -eq 429) {
                # Not usage: back off for what the instance asks, then retry the loop.
                $retry = 5
                $ra = $r.Headers['Retry-After']
                if ($ra) { try { $retry = [math]::Max(1, [int][string]$ra[0]) } catch {} }
                Start-Sleep -Seconds $retry
                continue
            }
            $sent++
        } catch {
            $codes['transport'] = 1 + [int]$codes['transport']
            Start-Sleep -Seconds 5
            continue
        }

        # Jittered pacing so the per-bucket counts vary like real integrations.
        if ($intervalMs -gt 0) { Start-Sleep -Milliseconds ($rng.Next([int]($intervalMs * 0.5), [int]($intervalMs * 1.5))) }
    }
    [pscustomobject]@{ Client = $c.AppName; Sent = $sent; Codes = $codes }
}

foreach ($r in $Results) {
    $summary = ($r.Codes.GetEnumerator() | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Value)" }) -join ', '
    Write-Host ("{0,-22} served={1,-6} {2}" -f $r.Client, $r.Sent, $summary) -ForegroundColor Green
}
Write-Host "Open Advanced > Container Management > Diagnostics; samples land every 5 minutes."
