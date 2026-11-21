function Push-CloudBackupJobCleanup {
    <#
    .SYNOPSIS
        Removes an expired cloud backup export, or all stored data and the record of an old restore or export job
    .DESCRIPTION
        Scope Export deletes the job's export zip and its versions and marks the export removed. Scope All also deletes
        the job's manifests and results under <policyId>/jobs/<jobId>/ and then the job record. At most 5000 objects or
        versions are deleted per call; the rest is left for the next cleanup. Versions that the destination refuses to
        delete expire with the policy's retention.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param($Item)

    $JobId = "$($Item.JobId)"
    $Scope = if ("$($Item.Scope)" -eq 'All') { 'All' } else { 'Export' }
    $Budget = 5000

    try {
        if (-not ($JobId -as [guid])) { throw "Cloud backup job id '$JobId' is not valid" }
        $Table = Get-CIPPTable -TableName 'CloudBackupJobs'
        $Job = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CloudBackupJob' and RowKey eq '$([guid]$JobId)'")[0]
        if (-not $Job) { return }

        $Prefixes = [System.Collections.Generic.List[string]]::new()
        if ($Job.ExportKey -and -not $Job.ExportRemovedAt) { $Prefixes.Add("$($Job.ExportKey)") }
        if ($Scope -eq 'All' -and $Job.PolicyId) { $Prefixes.Add("$($Job.PolicyId)/jobs/$($Job.RowKey)/") }

        $Complete = $true
        $Policy = if ($Prefixes.Count -gt 0) { Get-CIPPCloudBackupPolicy -Id $Job.PolicyId }
        $Destination = if ($Policy) { Get-CIPPCloudBackupDestination -Id $Policy.DestinationId -IncludeSecret }
        if ($Destination) {
            foreach ($Prefix in $Prefixes) {
                foreach ($Object in @(Get-CIPPCloudBackupObjectList -Destination $Destination -Prefix $Prefix)) {
                    if ($null -eq $Object) { continue }
                    if ($Budget -le 0) { $Complete = $false; break }
                    if ($PSCmdlet.ShouldProcess($Object.Key, 'Delete')) { Remove-CIPPCloudBackupObject -Destination $Destination -Key $Object.Key -Confirm:$false }
                    $Budget--
                }
                try {
                    foreach ($Version in @(Get-CIPPCloudBackupObjectVersionList -Destination $Destination -Prefix $Prefix)) {
                        if ($null -eq $Version -or -not $Version.VersionId) { continue }
                        if ($Budget -le 0) { $Complete = $false; break }
                        if ($PSCmdlet.ShouldProcess($Version.Key, 'Delete version')) { Remove-CIPPCloudBackupObject -Destination $Destination -Key $Version.Key -VersionId $Version.VersionId -Confirm:$false }
                        $Budget--
                    }
                } catch {
                    $ErrorMessage = Get-CippException -Exception $_
                    Write-LogMessage -API 'CloudBackupRestore' -message "Old versions of cloud backup job $JobId data could not be deleted and expire with the policy's retention: $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
                }
            }
        }

        if (-not $Complete) {
            Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'CloudBackupJob'; RowKey = $Job.RowKey; CleanupQueuedAt = '' } -OperationType 'UpsertMerge'
            return
        }
        if ($Scope -eq 'All') {
            Remove-CIPPAzDataTableEntity @Table -Entity @(@{ PartitionKey = 'CloudBackupJob'; RowKey = $Job.RowKey }, @{ PartitionKey = 'CloudBackupJobResult'; RowKey = $Job.RowKey }) -Force
        } elseif ($Job.ExportKey) {
            Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'CloudBackupJob'; RowKey = $Job.RowKey; ExportRemovedAt = [datetime]::UtcNow.ToString('o'); CleanupQueuedAt = '' } -OperationType 'UpsertMerge'
            Write-LogMessage -API 'CloudBackupRestore' -tenant $Job.SourceTenant -tenantid $Job.SourceTenantId -message "Expired export $JobId of $($Job.SourceOwnerName) was deleted" -sev Info
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CloudBackupRestore' -message "Could not clean up cloud backup job $($JobId): $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}
