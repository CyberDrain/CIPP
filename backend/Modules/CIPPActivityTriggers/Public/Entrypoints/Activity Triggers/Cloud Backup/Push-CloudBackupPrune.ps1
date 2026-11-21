function Push-CloudBackupPrune {
    <#
    .SYNOPSIS
        Removes versions older than a cloud backup policy's retention from its Azure Blob destination and records the result on the policy
    .DESCRIPTION
        Removes at most 5000 versions per run; the next daily run continues where this one stopped.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $PolicyId = "$($Item.PolicyId)"
    $MaxDeletes = 5000
    $Status = 'Failed'
    $ErrorText = ''
    $Skipped = 0
    $Policy = $null
    try {
        $Policy = Get-CIPPCloudBackupPolicy -Id $PolicyId
        if (-not $Policy) { return }
        $Destination = Get-CIPPCloudBackupDestination -Id $Policy.DestinationId -IncludeSecret
        if (-not $Destination) { throw "Destination $($Policy.DestinationId) no longer exists" }

        $Result = Remove-CIPPCloudBackupExpiredVersion -Destination $Destination -Prefix "$PolicyId/" -Days $Policy.RetentionDays -MaxDeletes $MaxDeletes
        $Skipped = [int]$Result.Skipped
        if ([int]$Result.Failed -gt 0) {
            $ErrorText = "$([int]$Result.Failed) old versions could not be removed: $(@($Result.Errors | Select-Object -First 5) -join '; ')"
        } else {
            $Status = if ([int]$Result.Deleted -ge $MaxDeletes) { 'Partial' } else { 'Succeeded' }
        }
    } catch {
        $ErrorText = "$((Get-CippException -Exception $_).NormalizedError)"
    }

    if ($ErrorText) {
        Write-LogMessage -API 'CloudBackup' -message "Cloud backup policy $($Policy.Name ?? $PolicyId): could not remove versions older than the retention: $ErrorText" -sev Warning
    }
    try {
        $Table = Get-CIPPTable -TableName 'Config'
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = 'CloudBackupPolicy'
            RowKey       = $PolicyId
            PruneStatus  = $Status
            PruneError   = $ErrorText
            PruneSkipped = $Skipped
        } -OperationType 'UpsertMerge'
    } catch {
        Write-Information "Could not record the prune result of cloud backup policy $($PolicyId): $($_.Exception.Message)"
    }
}
