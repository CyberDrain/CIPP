function Invoke-ExecAuditLogRetentionConfig {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    .DESCRIPTION
        Reads (List) or sets how many days saved audit logs, and the related records kept with repeated activity alerts,
        are kept: 30 to 365, 180 when not set.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CIPPTable -TableName Config
    $Filter = "PartitionKey eq 'AuditLogRetention' and RowKey eq 'Settings'"

    if (-not $Request.Query.List) {
        $RetentionDays = $Request.Body.RetentionDays -as [int]
        $ValidationError = if ($RetentionDays -lt 30) {
            'Retention days must be at least 30 days'
        } elseif ($RetentionDays -gt 365) {
            'Retention days must be at most 365 days'
        }
        if ($ValidationError) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = [pscustomobject]@{'Results' = "Failed to set configuration: $ValidationError" }
                })
        }
    }

    $StatusCode = [HttpStatusCode]::OK
    $Results = try {
        if ($Request.Query.List) {
            $RetentionSettings = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            @{ RetentionDays = if ($RetentionSettings.RetentionDays) { [int]$RetentionSettings.RetentionDays } else { 180 } }
        } else {
            Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'AuditLogRetention'; RowKey = 'Settings'; RetentionDays = $RetentionDays } -Force | Out-Null
            Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Set saved audit log retention to $RetentionDays days" -Sev 'Info'
            "Successfully set saved audit log retention to $RetentionDays days"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to set saved audit log retention: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        "Failed to set configuration: $($ErrorMessage.NormalizedError)"
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = [pscustomobject]@{ 'Results' = $Results }
        })
}
