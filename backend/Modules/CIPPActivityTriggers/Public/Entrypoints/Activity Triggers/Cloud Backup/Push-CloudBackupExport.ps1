function Push-CloudBackupExport {
    <#
    .SYNOPSIS
        Runs a cloud backup export job
    .DESCRIPTION
        Writes the job's item manifest, then builds the export zip in the policy's destination. The zip can be
        downloaded for 7 days.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $JobId = "$($Item.JobId)"
    $Table = $null
    $Started = $false
    $TenantFilter = $null

    try {
        if (-not ($JobId -as [guid])) { throw "Cloud backup job id '$JobId' is not valid" }
        $Table = Get-CIPPTable -TableName 'CloudBackupJobs'
        $Job = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CloudBackupJob' and RowKey eq '$([guid]$JobId)'")[0]
        if (-not $Job) { throw "Cloud backup job $JobId was not found" }
        if ($Job.Status -in @('Completed', 'Failed')) { return }

        $Now = [datetime]::UtcNow.ToString('o')
        Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'CloudBackupJob'; RowKey = $Job.RowKey; Status = 'Running'; StartedAt = if ($Job.StartedAt) { "$($Job.StartedAt)" } else { $Now }; UpdatedAt = $Now } -OperationType 'UpsertMerge'
        $Started = $true

        $Context = Get-CIPPCloudBackupJobContext -Job $Job
        $TenantFilter = $Context.TenantFilter
        Write-LogMessage -API 'CloudBackupRestore' -tenant $TenantFilter -tenantid $Context.TenantId -message "Export $JobId started for $($Job.RequestedBy): $($Context.Workload) backup of $($Job.SourceOwnerName) ($($Context.RunStamp))" -sev Info

        $ItemCount = [int]($Job.ItemCount -as [int])
        if ("$($Job.ManifestReady)" -ne 'True') {
            $Parameters = if ($Job.Parameters) { [CIPP.CippJson]::ConvertFromJson([string]$Job.Parameters) } else { $null }
            $Manifest = Save-CIPPCloudBackupJobManifest -Context $Context -Keys @($Parameters.Keys) -Paths @($Parameters.Paths)
            $ItemCount = [int]$Manifest.Items
            Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'CloudBackupJob'; RowKey = $Job.RowKey; ManifestReady = $true; ItemCount = $ItemCount; UpdatedAt = [datetime]::UtcNow.ToString('o') } -OperationType 'UpsertMerge'
        }

        $Export = Invoke-CIPPCloudBackupExport -Context $Context
        $Warnings = @(foreach ($Warning in @($Export.Warnings)) { if ($Warning) { "$Warning" } })
        $Summary = [ordered]@{ Items = $ItemCount; Exported = [int]$Export.Items; Failed = [int]$Export.Failed; Bytes = [int64]$Export.Bytes; Warnings = $Warnings.Count }
        $Completed = [datetime]::UtcNow
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = 'CloudBackupJob'
            RowKey       = $Job.RowKey
            Status       = 'Completed'
            ExportKey    = "$($Export.Key)"
            ExportBytes  = [int64]$Export.Bytes
            ExpiresAt    = $Completed.AddDays(7).ToString('o')
            Warnings     = [CIPP.CippJson]::ToJson([string[]]@(if ($Warnings.Count -gt 50) { $Warnings[0..49] } else { $Warnings }), 2) ?? '[]'
            Summary      = [CIPP.CippJson]::ToJson($Summary, 2) ?? (ConvertTo-Json -InputObject $Summary -Compress)
            CompletedAt  = $Completed.ToString('o')
            UpdatedAt    = $Completed.ToString('o')
            Error        = ''
        } -OperationType 'UpsertMerge'
        $Severity = if ($Summary.Failed -gt 0) { 'Warning' } else { 'Info' }
        Write-LogMessage -API 'CloudBackupRestore' -tenant $TenantFilter -tenantid $Context.TenantId -message "Export $JobId requested by $($Job.RequestedBy) of $($Job.SourceOwnerName) completed: $($Summary.Exported) of $ItemCount item(s) exported, $($Summary.Failed) failed, $($Summary.Bytes) bytes" -sev $Severity
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $ErrorText = "$($ErrorMessage.NormalizedError)"
        if ($Started) {
            try {
                Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'CloudBackupJob'; RowKey = "$([guid]$JobId)"; Status = 'Failed'; Error = $ErrorText; CompletedAt = [datetime]::UtcNow.ToString('o'); UpdatedAt = [datetime]::UtcNow.ToString('o') } -OperationType 'UpsertMerge'
            } catch {
                Write-Information "Could not record cloud backup job $($JobId): $($_.Exception.Message)"
            }
        }
        try { Write-LogMessage -API 'CloudBackupRestore' -tenant $TenantFilter -message "Cloud backup export job $JobId failed: $ErrorText" -sev Error -LogData $ErrorMessage } catch { Write-Information $ErrorText }
    }
}
