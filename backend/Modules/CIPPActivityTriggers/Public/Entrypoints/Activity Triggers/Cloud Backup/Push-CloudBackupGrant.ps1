function Push-CloudBackupGrant {
    <#
    .SYNOPSIS
        Grants the CIPP app the permissions a cloud backup policy needs in one tenant and records the result
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $PolicyId = "$($Item.PolicyId)"
    $TenantId = "$($Item.customerId)"
    try {
        $Policy = Get-CIPPCloudBackupPolicy -Id $PolicyId
        if (-not $Policy) { return }
        $Grant = Grant-CIPPCloudBackupPermission -TenantFilter $TenantId -Workloads $Policy.Workloads
        $Table = Get-CIPPTable -TableName 'CloudBackupPermissions'
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey = $PolicyId
            RowKey       = $TenantId
            Status       = $Grant.Status
            Message      = "$($Grant.Message)"
            CheckedAt    = $Grant.CheckedAt
            Workloads    = [CIPP.CippJson]::ToJson($Policy.Workloads, 2) ?? (ConvertTo-Json -InputObject @($Policy.Workloads) -Compress)
        } -Force
        $Severity = if ($Grant.Status -eq 'Granted') { 'Info' } else { 'Warning' }
        $Detail = if ($Grant.Message) { ": $($Grant.Message)" } else { '' }
        Write-LogMessage -API 'CloudBackup' -tenant "$($Item.QueueName ?? $TenantId)" -tenantid $TenantId -message "Cloud backup policy $($Policy.Name): permissions $($Grant.Status.ToLower())$Detail" -sev $Severity
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CloudBackup' -tenantid $TenantId -message "Could not record cloud backup permissions for policy $($PolicyId): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
