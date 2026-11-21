function Push-CloudBackupOwnerRemoved {
    <#
    .SYNOPSIS
        Marks every backed-up item of an owner that left the tenant or the policy as deleted, so it expires after the retention
    .DESCRIPTION
        Deletes up to 5000 items per run and writes their deletions as index parts; the next backup run of the tenant
        continues where this one stopped. When nothing is left the owner's state row is marked Removed with the reason
        (Removed or Excluded). The owner's backup state is cleared first so an owner that comes back is backed up in full.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $PolicyId = "$($Item.PolicyId)"
    $TenantId = "$($Item.customerId)"
    $Workload = "$($Item.Workload)".ToLowerInvariant()
    $OwnerId = "$($Item.OwnerId)"
    $Reason = if ("$($Item.Reason)" -eq 'Excluded') { 'Excluded' } else { 'Removed' }
    $SafeOwnerId = $OwnerId -replace "[/\\#?'\u0000-\u001F\u007F-\u009F]", '_'
    $MaxRemovals = 5000
    $PageSize = 1000

    try {
        $Policy = Get-CIPPCloudBackupPolicy -Id $PolicyId
        if (-not $Policy) { return }
        if ($Workload -notin @('exchange', 'onedrive', 'sharepoint', 'teams')) { throw "Unknown cloud backup workload '$Workload'" }
        $Destination = Get-CIPPCloudBackupDestination -Id $Policy.DestinationId -IncludeSecret
        if (-not $Destination) { throw "Destination $($Policy.DestinationId) no longer exists" }
        $KeyId = $null
        $Key = $null
        if ($Policy.Encryption) {
            if (-not $Policy.CurrentKeyId) { throw 'Encryption is on but the policy has no encryption key' }
            $KeyId = $Policy.CurrentKeyId
            $Key = Get-CIPPCloudBackupKey -KeyId $KeyId
        }

        $StateTable = Get-CIPPTable -TableName 'CloudBackupState'
        $StatePartition = "$($Policy.Id)_$TenantId"
        $StateRowKey = "$($Workload)_$SafeOwnerId"
        $Stored = @(Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$StatePartition' and RowKey eq '$StateRowKey'" -Property PartitionKey, RowKey, Removed)[0]
        if (-not $Stored -or "$($Stored.Removed)" -eq 'True') { return }
        Add-CIPPAzDataTableEntity @StateTable -Entity @{ PartitionKey = $StatePartition; RowKey = $StateRowKey; State = '' } -OperationType 'UpsertMerge'

        $Start = [datetime]::UtcNow
        $Context = [pscustomobject]@{
            PolicyId    = $Policy.Id
            TenantId    = $TenantId
            Workload    = $Workload
            OwnerId     = $OwnerId
            Destination = $Destination
            KeyId       = $KeyId
            Key         = $Key
            OwnerPrefix = "$($Policy.Id)/$TenantId/$Workload/$SafeOwnerId/"
        }
        # Later than the listing's AsOf so the deletions written here don't shift the pages being read
        $RunStamp = $Start.AddSeconds(1).ToString('yyyyMMddTHHmmssZ')
        $Skip = 0
        $Part = 0
        $Removed = 0
        $Failed = 0
        $Errors = [System.Collections.Generic.List[string]]::new()
        $Done = $false

        while (($Removed + $Failed) -lt $MaxRemovals) {
            $Listing = Get-CIPPCloudBackupOwnerListing -Destination $Destination -OwnerPrefix $Context.OwnerPrefix -AsOf $Start -IncludeFolders -Skip $Skip -Take $PageSize
            $Page = @($Listing.Items)
            if ($Page.Count -eq 0) { $Done = $true; break }

            $Entries = [System.Collections.Generic.List[object]]::new()
            foreach ($Entry in $Page) {
                try {
                    if ($Entry.Type -ne 'folder') { $null = Remove-CIPPCloudBackupItem -Context $Context -ItemKey $Entry.Key }
                    if ($Entry.Extra.eml) { $null = Remove-CIPPCloudBackupItem -Context $Context -ItemKey "$($Entry.Extra.eml)" }
                    foreach ($Hosted in @($Entry.Extra.hostedContents)) {
                        if ($Hosted) { $null = Remove-CIPPCloudBackupItem -Context $Context -ItemKey "$Hosted" }
                    }
                } catch {
                    $Failed++
                    if ($Errors.Count -lt 5) { $Errors.Add("$($Entry.Key): $($_.Exception.Message)") }
                    continue
                }
                $Removed++
                $Entries.Add([pscustomobject]@{ k = $Entry.Key; p = $Entry.Path; n = $Entry.Name; t = $Entry.Type; s = $null; m = $null; v = $null; d = $true; x = $Entry.Extra })
            }

            if ($Entries.Count -gt 0) {
                $Buffer = [System.IO.MemoryStream]::new()
                try {
                    $Gzip = [System.IO.Compression.GZipStream]::new($Buffer, [System.IO.Compression.CompressionLevel]::Optimal, $true)
                    $Writer = [System.IO.StreamWriter]::new($Gzip, [System.Text.UTF8Encoding]::new($false))
                    foreach ($IndexEntry in $Entries) {
                        $Writer.Write(([CIPP.CippJson]::ToJson($IndexEntry, 10) ?? (ConvertTo-Json -InputObject $IndexEntry -Depth 10 -Compress)))
                        $Writer.Write("`n")
                    }
                    $Writer.Dispose()
                    $Buffer.Position = 0
                    $IndexKey = 'index/{0}-{1:D5}.jsonl.gz' -f $RunStamp, $Part
                    if ($Key) { $IndexKey = "$IndexKey.enc" }
                    $null = Write-CIPPCloudBackupItem -Context $Context -ItemKey $IndexKey -Stream $Buffer -ContentType 'application/gzip'
                } finally {
                    $Buffer.Dispose()
                }
                $Part++
            }

            $Skip += $Page.Count
            if ($Skip -ge [int]$Listing.Total) { $Done = $true; break }
        }

        $Name = "$($Item.DisplayName)"
        if (-not $Name) { $Name = $OwnerId }
        $Why = if ($Reason -eq 'Excluded') { 'is now excluded from the policy' } else { 'is no longer in the tenant' }
        if ($Done -and $Failed -eq 0) {
            Add-CIPPAzDataTableEntity @StateTable -Entity @{
                PartitionKey  = $StatePartition
                RowKey        = $StateRowKey
                Removed       = $true
                RemovedAt     = [datetime]::UtcNow.ToString('o')
                RemovedReason = $Reason
            } -OperationType 'UpsertMerge'
            Write-LogMessage -API 'CloudBackup' -tenantid $TenantId -message "Cloud backup $($Policy.Name) ($Workload): $Name $Why; its $Removed backed-up items expire after $($Policy.RetentionDays) days" -sev Info
        } elseif ($Failed -gt 0) {
            Write-LogMessage -API 'CloudBackup' -tenantid $TenantId -message "Cloud backup $($Policy.Name) ($Workload): $Name $Why; $Failed items could not be marked deleted and will be retried on the next run: $($Errors -join '; ')" -sev Warning
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CloudBackup' -tenantid $TenantId -message "Cloud backup: could not mark the items of $($Item.DisplayName ?? $OwnerId) ($Workload) deleted: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
