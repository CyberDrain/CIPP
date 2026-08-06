function Start-CIPPTaskPreflightCheck {
    <#
    .SYNOPSIS
    Flag planned scheduled tasks whose prerequisites are no longer available

    .DESCRIPTION
    A task scheduled days in advance can become undeliverable long before it runs. The clearest case is a
    scheduled user creation that needs a licence: the licence is available when the job is booked, gets
    consumed by someone else in the meantime, and the job only fails once the scheduled time arrives.

    This walks the planned tasks that depend on a licence and compares what they ask for against what the
    tenant actually has left, marking the ones that would fail today so they can be dealt with in advance
    rather than discovered afterwards.

    Only tasks that reference licences are inspected, so the cost scales with the number of licence-bearing
    scheduled tasks rather than the size of the table.

    .FUNCTIONALITY
    Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $Table = Get-CippTable -tablename 'ScheduledTasks'
    $Filter = "PartitionKey eq 'ScheduledTask' and TaskState eq 'Planned'"
    $Tasks = Get-CIPPAzDataTableEntity @Table -Filter $Filter

    Write-Information "Preflight: retrieved $(($Tasks | Measure-Object).Count) planned scheduled tasks."

    # Work out which tasks depend on a licence, and which SKUs each one needs.
    $LicenseTasks = [System.Collections.Generic.List[object]]::new()
    foreach ($Task in $Tasks) {
        if (!$Task.Command -or !$Task.Parameters) { continue }

        try {
            $Parameters = $Task.Parameters | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Write-Information "Preflight: could not parse parameters for task $($Task.RowKey), skipping."
            continue
        }

        # A Sherweb-backed creation buys the subscription during the run before assigning it, so the
        # tenant having none right now says nothing about whether the task will succeed. Flagging
        # those would be a false alarm on every single one.
        if ($Task.Command -eq 'New-CIPPUserTask' -and $Parameters.UserObj.sherwebLicense.value) {
            Write-Information "Preflight: task $($Task.RowKey) buys a Sherweb licence at run time, skipping."
            continue
        }

        $RequestedSkus = switch ($Task.Command) {
            'New-CIPPUserTask' { @($Parameters.UserObj.licenses.value) }
            'Set-CIPPUserLicense' { @($Parameters.AddLicenses) }
            default { @() }
        }

        $RequestedSkus = @($RequestedSkus | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($RequestedSkus.Count -eq 0) { continue }

        # Tenant on the row is the display value; the parameters carry the authoritative filter.
        $TenantFilter = $Parameters.UserObj.tenantFilter ?? $Parameters.TenantFilter ?? $Task.Tenant
        if ([string]::IsNullOrWhiteSpace($TenantFilter) -or $TenantFilter -eq 'AllTenants') { continue }

        $LicenseTasks.Add([PSCustomObject]@{
                Task         = $Task
                TenantFilter = $TenantFilter
                Skus         = $RequestedSkus
            })
    }

    if ($LicenseTasks.Count -eq 0) {
        Write-Information 'Preflight: no planned tasks depend on a licence.'
        return
    }

    Write-Information "Preflight: checking $($LicenseTasks.Count) licence-dependent task(s)."

    # One subscribedSkus call per distinct tenant, not per task. Deliberately not Get-CIPPLicenseOverview,
    # which also expands every assigned user and group and is far more than is needed here.
    # Loaded once, not per SKU: Convert-SKUname re-reads the conversion CSV on every call otherwise.
    $ConvertTable = try {
        [System.IO.File]::ReadAllText((Join-Path $env:CIPPRootPath 'Config\ConversionTable.csv')) | ConvertFrom-Csv
    } catch { $null }
    function Get-FriendlySkuName {
        param($SkuId, $Fallback)
        $Name = if ($ConvertTable) { Convert-SKUname -SkuID $SkuId -ConvertTable $ConvertTable }
        # Unmapped SKUs come back as an array of the inputs rather than a name - use the fallback then.
        if ($Name -is [string] -and -not [string]::IsNullOrWhiteSpace($Name)) { $Name } else { $Fallback }
    }

    $AvailabilityByTenant = @{}
    foreach ($TenantFilter in ($LicenseTasks.TenantFilter | Sort-Object -Unique)) {
        try {
            $Skus = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/subscribedSkus' -tenantid $TenantFilter
            $Available = @{}
            foreach ($Sku in $Skus) {
                $Available[([string]$Sku.skuId).ToLowerInvariant()] = [PSCustomObject]@{
                    Available     = [int]$Sku.prepaidUnits.enabled - [int]$Sku.consumedUnits
                    SkuPartNumber = $Sku.skuPartNumber
                }
            }
            $AvailabilityByTenant[$TenantFilter] = $Available
        } catch {
            # A tenant we cannot read is not evidence that anything is wrong, so leave its tasks alone
            # rather than flagging them on a lookup failure.
            Write-Information "Preflight: could not read licences for $TenantFilter, skipping its tasks. $($_.Exception.Message)"
        }
    }

    foreach ($Entry in $LicenseTasks) {
        $Available = $AvailabilityByTenant[$Entry.TenantFilter]
        if ($null -eq $Available) { continue }

        $Task = $Entry.Task
        # One list per task; licence availability is the first check, but anything that can predict a
        # failure cheaply belongs here - a username already taken, a target mailbox or group that has
        # been deleted, a tenant that is no longer reachable. Add to $Problems and the flag, reason,
        # view and notifications all follow without further wiring.
        $Problems = [System.Collections.Generic.List[string]]::new()

        foreach ($Sku in $Entry.Skus) {
            $SkuKey = ([string]$Sku).ToLowerInvariant()
            if (!$Available.ContainsKey($SkuKey)) {
                $Problems.Add("the tenant no longer has a subscription for $(Get-FriendlySkuName -SkuId $Sku -Fallback "SKU $Sku")")
            } elseif ($Available[$SkuKey].Available -lt 1) {
                $Problems.Add("no licences available for $(Get-FriendlySkuName -SkuId $Sku -Fallback $Available[$SkuKey].SkuPartNumber)")
            }
        }

        $IsAtRisk = $Problems.Count -gt 0
        $WasAtRisk = [bool]$Task.AtRisk
        $Reason = if ($IsAtRisk) { "This task will fail as scheduled: $($Problems -join '; ')." } else { '' }

        # Nothing changed at all, so nothing to write - that keeps the ETag stable for the
        # orchestrator's claim. The reason is compared as well as the flag: a task can stay at risk
        # while the cause changes (the licences run out, then the subscription itself goes away), and
        # the reason is what someone acts on, so letting it go stale defeats the point.
        if ($IsAtRisk -eq $WasAtRisk -and $Reason -eq [string]$Task.AtRiskReason) { continue }

        $Action = if ($IsAtRisk) { 'Flag as at risk' } else { 'Clear at-risk flag' }
        if (-not $PSCmdlet.ShouldProcess($Task.Name, $Action)) { continue }

        Update-AzDataTableEntity -Force @Table -Entity @{
            PartitionKey = $Task.PartitionKey
            RowKey       = $Task.RowKey
            AtRisk       = $IsAtRisk
            AtRiskReason = $Reason
        }

        if ($IsAtRisk -and -not $WasAtRisk) {
            # Only on the transition into at-risk, so a task left flagged for a week does not
            # re-notify on every run of this timer. A reason that changes while the task stays at
            # risk updates the row above but is not worth alerting on again.
            # Deliberately its own API name rather than Scheduler_UserTasks: at-risk is a prediction
            # about a task that has not run, and admins may want those notifications separately from
            # (or instead of) actual failures.
            Write-LogMessage -API 'Scheduler_Preflight' -tenant $Entry.TenantFilter -message "Scheduled task '$($Task.Name)' is at risk: $($Problems -join '; ')." -sev Error
        } elseif ($IsAtRisk) {
            Write-Information "Preflight: task $($Task.RowKey) is still at risk, reason updated."
        } else {
            Write-Information "Preflight: task $($Task.RowKey) is no longer at risk."
        }
    }
}
