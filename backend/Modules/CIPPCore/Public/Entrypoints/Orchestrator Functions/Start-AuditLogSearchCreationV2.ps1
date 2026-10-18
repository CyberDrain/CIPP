function Start-AuditLogSearchCreationV2 {
    <#
    .SYNOPSIS
        V2 audit-log search creation timer. Plans 35-minute windows per tenant in the AuditLogCoverage
        ledger and fans out creation, in chunks of tenants, only to tenants that owe a window or have a
        retry due.
    .DESCRIPTION
        Tenants: those with Webhookv2 WebhookRules, minus excluded, minus auditing-disabled.
        The key points:
          * Windows are clock-aligned, 35 minutes on a 30-minute stride, so consecutive windows
            OVERLAP by 5 minutes (tracked in AuditLogCoverage). The overlap is deliberate - it
            covers records landing on a boundary - and is safe only because alerting de-duplicates
            by record id, which it does in exactly one place: the claim-insert into AuditLogs in
            Invoke-CippWebhookProcessing. Nothing downstream of that de-duplicates.
          * Failed creations are recorded as Planned/Retry ledger rows, so they are retried (and gaps
            backfilled) instead of being silently dropped.
          * "First check what tenants need searches created" - the timer scans the ledger once and
            only fans out tenants that owe a window or have a due retry.
          * Tenants are fanned out in chunks of -TenantsPerTask (100). Each activity creates its tenants'
            searches in one concurrent multi-tenant Graph call, so a few hundred tenants are a handful
            of tasks rather than one task each.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [int]$TenantsPerTask = 100
    )
    try {
        $InScope = @(Get-CIPPAuditLogTenantScope)
        if ($InScope.Count -eq 0) {
            Write-Information 'AuditLogV2: no in-scope tenants'
            return
        }

        # --- Scan ledger once, group by tenant ---
        $Ledger = Get-CippTable -TableName 'AuditLogCoverage'
        # Cover the reconciliation horizon (48h) plus slack so the fan-out check sees existing recon rows.
        $HorizonIso = (Get-Date).AddHours(-50).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        # Projected to the five columns actually consumed: PartitionKey to group by tenant, State
        # and NextAttemptUtc for the due-retry test below, and RowKey plus WindowStart for the two
        # window planners. Timestamp is not a key, so this is a cross-partition scan whatever the
        # predicate - what is controllable is how much comes back over the wire. At a few hundred
        # tenants this covers roughly 90 windows each across the 50-hour horizon, and it ran every
        # cycle pulling every column of every one of them.
        $AllRows = Get-CIPPAzDataTableEntity @Ledger -Filter "Timestamp ge datetime'$HorizonIso'" `
            -Property PartitionKey, RowKey, State, NextAttemptUtc, WindowStart
        $ByTenant = @{}
        foreach ($Row in $AllRows) {
            if (-not $ByTenant.ContainsKey($Row.PartitionKey)) { $ByTenant[$Row.PartitionKey] = [System.Collections.Generic.List[object]]::new() }
            $ByTenant[$Row.PartitionKey].Add($Row)
        }

        $Now = (Get-Date).ToUniversalTime()
        $Owing = foreach ($Tenant in $InScope) {
            $Rows = if ($ByTenant.ContainsKey($Tenant.defaultDomainName)) { $ByTenant[$Tenant.defaultDomainName] } else { @() }
            $Owed = Get-CippAuditLogPlannedWindows -ExistingRows $Rows -Now $Now
            $OwedRecon = Get-CippAuditLogReconciliationWindows -ExistingRows $Rows -Now $Now
            $DuePlanned = @($Rows | Where-Object { $_.State -eq 'Planned' -and (-not $_.NextAttemptUtc -or ([datetimeoffset]$_.NextAttemptUtc).UtcDateTime -le $Now) })
            if (($Owed.Count -gt 0) -or ($OwedRecon.Count -gt 0) -or ($DuePlanned.Count -gt 0)) {
                [PSCustomObject]@{
                    TenantFilter = $Tenant.defaultDomainName
                    TenantId     = [string]$Tenant.customerId
                }
            }
        }
        $Owing = @($Owing)
        $Batch = for ($i = 0; $i -lt $Owing.Count; $i += $TenantsPerTask) {
            [PSCustomObject]@{
                FunctionName = 'AuditLogSearchCreationV2'
                Tenants      = @($Owing[$i..([Math]::Min($i + $TenantsPerTask - 1, $Owing.Count - 1))])
            }
        }
        $Batch = @($Batch)

        if ($Batch.Count -gt 0) {
            Write-Information "AuditLogV2: $($Owing.Count) tenant(s) need search creation, in $($Batch.Count) task(s)"
            if ($PSCmdlet.ShouldProcess('Start-AuditLogSearchCreationV2', 'Create audit log searches')) {
                $InputObject = [PSCustomObject]@{
                    OrchestratorName = 'AuditLogSearchCreationV2'
                    AllowCollision   = $false
                    Batch            = @($Batch)
                    SkipLog          = $true
                    Priority         = 3
                }
                Start-CIPPOrchestrator -InputObject $InputObject
            }
        } else {
            Write-Information 'AuditLogV2: no tenants need searches this run'
        }

        # --- Best-effort retention: drop ledger rows older than 7 days (all states; active windows are < 26h old) ---
        try {
            $CutoffIso = (Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            $Stale = @(Get-CIPPAzDataTableEntity @Ledger -Filter "Timestamp le datetime'$CutoffIso'" -Property PartitionKey, RowKey)
            if ($Stale.Count -gt 0) {
                Remove-CIPPAzDataTableEntity @Ledger -Entity $Stale -Force
                Write-Information "AuditLogV2: cleaned $($Stale.Count) stale ledger row(s)"
            }
        } catch {
            Write-Information "AuditLogV2: ledger cleanup skipped - $($_.Exception.Message)"
        }
    } catch {
        Write-LogMessage -API 'AuditLogV2' -message 'Error creating audit log searches (V2)' -sev Error -LogData (Get-CippException -Exception $_)
        Write-Information ('AuditLogV2 create error {0} line {1} - {2}' -f $_.InvocationInfo.ScriptName, $_.InvocationInfo.ScriptLineNumber, $_.Exception.Message)
    }
}
