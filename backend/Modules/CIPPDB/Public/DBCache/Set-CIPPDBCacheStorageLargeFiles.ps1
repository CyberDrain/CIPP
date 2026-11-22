function Set-CIPPDBCacheStorageLargeFiles {
    <#
    .SYNOPSIS
        Fans out the SharePoint large file scan, batched by site.

    .DESCRIPTION
        Takes the sites from the cached SharePoint usage report, keeps those holding at least 1 GB, and starts a
        child orchestration with one activity per batch of 10 sites (Push-DBCacheStorageLargeFilesBatch). A single
        PostExecution (Push-StoreStorageLargeFiles) writes the StorageLargeFiles cache once. Without usage figures
        the run fails and the earlier scan is left in place. A site with no usage figure is not scanned and keeps its
        earlier rows; earlier rows are cleared only for sites whose usage figure is below 1 GB.

        Report-private: rows live in the CippStorageLargeFiles table, read only by the storage report. The rows
        carry file names and paths, so this is run on demand and is not part of nightly CIPPDB collection.

    .PARAMETER TenantFilter
        The tenant to scan for large files

    .PARAMETER QueueId
        Optional queue ID for progress tracking
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    $BatchSize = 10
    $MinimumSiteBytes = 1GB

    try {
        $LicenseCheck = Test-CIPPStandardLicense -StandardName 'StorageLargeFilesCache' -TenantFilter $TenantFilter -Preset SharePoint -SkipLog
        if ($LicenseCheck -eq $false) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Tenant does not have a SharePoint license, skipping StorageLargeFiles cache' -sev Debug
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'StorageLargeFiles' -TableName 'CippStorageLargeFiles' -Data @() -AddCount -ClearOnEmpty
            return
        }

        # Sites come from the usage sync, so a site too small to hold a large file is never read.
        $NoUsage = 'No SharePoint usage figures are stored for this tenant yet. Run Sync usage on the Storage Report first, then scan for large files again.'
        $UsageRows = try { @(Get-CIPPSharePointSiteUsageReport -TenantFilter $TenantFilter -ErrorAction Stop) } catch { throw $NoUsage }
        $Sites = [System.Collections.Generic.List[object]]::new()
        # A site without a usage figure is not scanned and keeps its earlier rows.
        $Unmeasured = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $HasUsage = $false
        foreach ($Site in $UsageRows) {
            if ($null -eq $Site.storageUsedInBytes) {
                if ($Site.webUrl) { $null = $Unmeasured.Add(([string]$Site.webUrl).TrimEnd('/')) }
                continue
            }
            $HasUsage = $true
            if ($Site.webUrl -and [double]$Site.storageUsedInBytes -ge $MinimumSiteBytes) {
                $Sites.Add([PSCustomObject]@{ webUrl = $Site.webUrl; displayName = $Site.displayName })
            }
        }
        if (-not $HasUsage) { throw $NoUsage }

        if ($Sites.Count -eq 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "No SharePoint site holds 1 GB or more; clearing StorageLargeFiles except for $($Unmeasured.Count) sites without a usage figure" -sev Debug
            $Kept = if ($Unmeasured.Count -gt 0) {
                foreach ($Row in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'StorageLargeFiles' -TableName 'CippStorageLargeFiles')) {
                    if ($Row.rowType -eq 'File' -and $Unmeasured.Contains([string]$Row.siteUrl)) { $Row }
                }
            }
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'StorageLargeFiles' -TableName 'CippStorageLargeFiles' -Data @($Kept) -AddCount -ClearOnEmpty
            return
        }

        $Batches = [System.Collections.Generic.List[object]]::new()
        $TotalBatches = [Math]::Ceiling($Sites.Count / $BatchSize)
        for ($BatchNumber = 1; $BatchNumber -le $TotalBatches; $BatchNumber++) {
            $Start = ($BatchNumber - 1) * $BatchSize
            $BatchItem = [PSCustomObject]@{
                FunctionName = 'DBCacheStorageLargeFilesBatch'
                TenantFilter = $TenantFilter
                QueueName    = "Storage Large Files Batch $BatchNumber/$TotalBatches - $TenantFilter"
                BatchNumber  = $BatchNumber
                TotalBatches = $TotalBatches
                Sites        = @($Sites[$Start..[Math]::Min($Start + $BatchSize - 1, $Sites.Count - 1)])
            }
            if ($QueueId) {
                $BatchItem.PSObject.Properties.Add([psnoteproperty]::new('QueueId', $QueueId))
            }
            $Batches.Add($BatchItem)
        }

        if ($QueueId) {
            try {
                Update-CippQueueEntry -RowKey $QueueId -TotalTasks $Batches.Count -IncrementTotalTasks
            } catch {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Could not update queue $QueueId with StorageLargeFiles batch tasks: $($_.Exception.Message)" -sev Warning
            }
        }

        $null = Start-CIPPOrchestrator -InputObject ([PSCustomObject]@{
                Batch            = @($Batches)
                OrchestratorName = "StorageLargeFiles_$TenantFilter"
                AllowCollision   = $false
                MaxConcurrency   = 3
                SkipLog          = $true
                PostExecution    = @{
                    FunctionName = 'StoreStorageLargeFiles'
                    Parameters   = @{
                        TenantFilter     = $TenantFilter
                        ExpectedSiteUrls   = @(foreach ($Site in $Sites) { ([string]$Site.webUrl).TrimEnd('/') })
                        UnmeasuredSiteUrls = @($Unmeasured)
                    }
                }
            })
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Started StorageLargeFiles collection across $($Sites.Count) sites in $($Batches.Count) batches" -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to start StorageLargeFiles collection: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
