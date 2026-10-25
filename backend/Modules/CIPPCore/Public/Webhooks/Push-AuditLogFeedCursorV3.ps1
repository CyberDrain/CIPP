function Push-AuditLogFeedCursorV3 {
    <#
    .SYNOPSIS
        Post-execution for an AuditLogFeedBlobsV3 run: moves each feed's LastEndUtc to where its alerts are complete, then
        queues the cycle's next run.
    .DESCRIPTION
        A feed's alerts are complete up to just before its oldest AuditLogFeedBlobs row still pending (a row's RowKey
        starts with its blob's created ticks), or up to ListedThroughUtc when none is left. After a blob run (Run set),
        AuditLogFeedFanOutV3 queues the rows of the cycle not yet queued, if any. Threshold counts and alert rows older
        than 12 hours are removed from AuditLogFeedThresholds.
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    try {
        $Now = [datetime]::UtcNow
        $BlobTable = Get-CippTable -TableName 'AuditLogFeedBlobs'
        $CursorTable = Get-CippTable -TableName 'AuditLogFeedCursor'
        $Oldest = @{}
        foreach ($Row in @(Get-CIPPAzDataTableEntity @BlobTable -Property @('PartitionKey', 'RowKey', 'ContentType'))) {
            $Key = '{0}|{1}' -f $Row.PartitionKey, $Row.ContentType
            if (-not $Oldest.ContainsKey($Key) -or [string]::CompareOrdinal($Row.RowKey, $Oldest[$Key]) -lt 0) { $Oldest[$Key] = $Row.RowKey }
        }
        $Updates = foreach ($Cursor in @(Get-CIPPAzDataTableEntity @CursorTable)) {
            if (-not $Cursor.ListedThroughUtc) { continue }
            $Pending = $Oldest['{0}|{1}' -f $Cursor.PartitionKey, $Cursor.RowKey]
            $End = if ($Pending) { [datetime]::new([long]$Pending.Substring(0, 19), [System.DateTimeKind]::Utc).AddSeconds(-1) } else { ([datetimeoffset]$Cursor.ListedThroughUtc).UtcDateTime }
            if ($Cursor.LastEndUtc -and ([datetimeoffset]$Cursor.LastEndUtc).UtcDateTime -eq $End) { continue }
            @{ PartitionKey = $Cursor.PartitionKey; RowKey = $Cursor.RowKey; LastEndUtc = $End; CheckpointUtc = $Now }
        }
        $Updates = @($Updates)
        if ($Updates.Count -gt 0) { $null = Add-CIPPAzDataTableEntity @CursorTable -Entity $Updates -OperationType UpsertMerge }
        Write-Information "AuditLogFeedCursorV3: $($Updates.Count) cursor(s) moved, $($Oldest.Count) feed(s) with blobs pending"
        # Counts and claims outlive the furthest back the feed reads (6 hours) plus the longest window (60 minutes).
        $ThresholdTable = Get-CippTable -TableName 'AuditLogFeedThresholds'
        $Expired = @(Get-CIPPAzDataTableEntity @ThresholdTable -Filter "Timestamp lt datetime'$($Now.AddHours(-7).ToString('yyyy-MM-ddTHH:mm:ssZ'))'" -Property @('PartitionKey', 'RowKey'))
        if ($Expired.Count -gt 0) { Remove-CIPPAzDataTableEntity @ThresholdTable -Entity $Expired -Force }
    } catch {
        Write-LogMessage -API 'AuditLogFeedV3' -message 'Could not move the audit log feed cursors; the next run does' -sev Error -LogData (Get-CippException -Exception $_)
    }
    if ($Item.Parameters.Run) { Push-AuditLogFeedFanOutV3 -Item @{ Parameters = $Item.Parameters } }
}
