function Push-CloudBackupIndexMaintenance {
    <#
    .SYNOPSIS
        Compacts the backup index of one owner and removes index history older than the policy's retention
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $PolicyId = "$($Item.PolicyId)"
    $TenantId = "$($Item.customerId)"
    $Workload = "$($Item.Workload)".ToLowerInvariant()
    $OwnerKey = "$($Item.OwnerKey)"

    try {
        $Policy = Get-CIPPCloudBackupPolicy -Id $PolicyId
        if (-not $Policy) { return }
        if ($Workload -notin @('exchange', 'onedrive', 'sharepoint', 'teams')) { throw "Unknown cloud backup workload '$Workload'" }
        if (-not $OwnerKey -or "$OwnerKey$TenantId" -match "[/\\#?'\u0000-\u001F\u007F-\u009F]" -or -not $TenantId) { throw "Owner '$OwnerKey' of tenant '$TenantId' is not valid" }

        $StateTable = Get-CIPPTable -TableName 'CloudBackupState'
        $State = @(Get-CIPPAzDataTableEntity @StateTable -Filter "PartitionKey eq '$($Policy.Id)_$TenantId' and RowKey eq '$($Workload)_$OwnerKey'" -Property PartitionKey, RowKey, Status)[0]
        # A snapshot taken mid-run would hide the run's later index parts, which share its RunStamp
        if (-not $State -or "$($State.Status)" -eq 'Running') { return }

        $Destination = Get-CIPPCloudBackupDestination -Id $Policy.DestinationId -IncludeSecret
        if (-not $Destination) { throw "Destination $($Policy.DestinationId) no longer exists" }
        $KeyId = $null
        $Key = $null
        if ($Policy.Encryption) {
            if (-not $Policy.CurrentKeyId) { throw 'Encryption is on but the policy has no encryption key' }
            $KeyId = $Policy.CurrentKeyId
            $Key = Get-CIPPCloudBackupKey -KeyId $KeyId
        }

        $OwnerPrefix = "$($Policy.Id)/$TenantId/$Workload/$OwnerKey/"
        $null = Invoke-CIPPCloudBackupIndexCompaction -Destination $Destination -OwnerPrefix $OwnerPrefix -KeyId $KeyId -Key $Key -DeletedBefore ([datetime]::UtcNow.AddDays(-$Policy.RetentionDays))
        $null = Remove-CIPPCloudBackupIndexHistory -Destination $Destination -OwnerPrefix $OwnerPrefix -OlderThan ([datetime]::UtcNow.AddDays(-($Policy.RetentionDays + 1)))
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CloudBackup' -tenantid $TenantId -message "Cloud backup: could not maintain the backup index of $OwnerKey ($Workload): $($ErrorMessage.NormalizedError)" -sev Warning -LogData $ErrorMessage
    }
}
