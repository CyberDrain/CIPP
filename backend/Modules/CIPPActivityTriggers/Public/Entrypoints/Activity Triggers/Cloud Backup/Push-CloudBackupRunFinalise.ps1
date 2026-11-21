function Push-CloudBackupRunFinalise {
    <#
    .SYNOPSIS
        Post-execution for a cloud backup run: adds up the per-owner results into the run row
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $RunId = "$($Item.Parameters.RunId ?? $Item.RunId)"
    if ($RunId -notmatch '^([0-9a-fA-F-]{36})_(.+)$') {
        Write-Information "Cloud backup run id '$RunId' is not valid"
        return
    }
    $PolicyId = $Matches[1]
    $RowKey = $Matches[2]

    try {
        $RunsTable = Get-CIPPTable -TableName 'CloudBackupRuns'
        $Run = @(Get-CIPPAzDataTableEntity @RunsTable -Filter "PartitionKey eq '$PolicyId' and RowKey eq '$RowKey'")[0]
        if (-not $Run) { return }

        $OwnersTable = Get-CIPPTable -TableName 'CloudBackupRunOwners'
        $Owners = @(Get-CIPPAzDataTableEntity @OwnersTable -Filter "PartitionKey eq '$RunId'" -Property PartitionKey, RowKey, Status, Items, Bytes, Deleted)

        $Items = [int64]0
        $Bytes = [int64]0
        $Deleted = [int64]0
        $Succeeded = 0
        $Partial = 0
        $Failed = 0
        foreach ($Owner in $Owners) {
            $Items += [int64]($Owner.Items -as [int64])
            $Bytes += [int64]($Owner.Bytes -as [int64])
            $Deleted += [int64]($Owner.Deleted -as [int64])
            switch ("$($Owner.Status)") {
                'Succeeded' { $Succeeded++ }
                'PartialSuccess' { $Partial++ }
                default { $Failed++ }
            }
        }
        $Expected = [Math]::Max([int]($Run.Owners -as [int]), $Owners.Count)
        $Failed += $Expected - $Owners.Count

        $Warnings = [System.Collections.Generic.List[string]]::new()
        foreach ($Warning in @(if ($Run.Warnings) { [CIPP.CippJson]::ConvertFromJson([string]$Run.Warnings) })) { if ($Warning) { $Warnings.Add("$Warning") } }
        if ($Failed -gt 0) { $Warnings.Add("$Failed of $Expected $(if ($Expected -eq 1) { 'item' } else { 'items' }) failed or did not finish") }

        $Status = if ($Expected -eq 0 -or ($Failed -eq 0 -and $Partial -eq 0 -and $Warnings.Count -eq 0)) {
            'Succeeded'
        } elseif ($Failed -ge $Expected) {
            'Failed'
        } else {
            'PartialSuccess'
        }

        Add-CIPPAzDataTableEntity @RunsTable -Entity @{
            PartitionKey    = $PolicyId
            RowKey          = $RowKey
            Status          = $Status
            CompletedAt     = [datetime]::UtcNow.ToString('o')
            OwnersSucceeded = $Succeeded + $Partial
            OwnersFailed    = $Failed
            Items           = $Items
            Bytes           = $Bytes
            Deleted         = $Deleted
            Warnings        = [CIPP.CippJson]::ToJson($Warnings, 2) ?? (ConvertTo-Json -InputObject @($Warnings) -Compress)
        } -OperationType 'UpsertMerge'

        $Severity = switch ($Status) { 'Succeeded' { 'Info' } 'PartialSuccess' { 'Warning' } default { 'Error' } }
        Write-LogMessage -API 'CloudBackup' -tenant $Run.Tenant -tenantid $Run.TenantId -message "Cloud backup $($Run.PolicyName) ($($Run.Workload)) finished with status $($Status): $($Succeeded + $Partial) of $Expected backed up" -sev $Severity
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'CloudBackup' -message "Could not finish cloud backup run $($RunId): $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
    }
}
