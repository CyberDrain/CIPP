function Invoke-ExecAckScheduledItem {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Scheduler.ReadWrite
    .DESCRIPTION
        Acknowledges a scheduled task that completed with errors, removing it from the needs-attention
        view without erasing the failure record. HasErrors and ErrorSummary stay on the row - the task
        DID fail and the history should say so - but an acknowledged row no longer demands attention.
        A later run that fails again clears the acknowledgement, so a recurring problem re-surfaces.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers

    try {
        $RowKey = $Request.Body.RowKey ?? $Request.Query.RowKey
        if ([string]::IsNullOrWhiteSpace($RowKey)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = 'RowKey is required.' }
                })
        }

        $Table = Get-CIPPTable -TableName 'ScheduledTasks'
        $SafeRowKey = ConvertTo-CIPPODataFilterValue -Value $RowKey -Type String
        $Task = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ScheduledTask' and RowKey eq '$SafeRowKey'"
        if (!$Task) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Results = "No scheduled task found with id $RowKey." }
                })
        }

        if ($Task.HasErrors -ne $true -and $Task.TaskState -notin @('Failed', 'Failed - Planned')) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Task '$($Task.Name)' has no errors to acknowledge." }
                })
        }

        $AcknowledgedBy = try {
            ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Request.Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
        } catch { 'Unknown' }

        $null = Update-AzDataTableEntity -Force @Table -Entity @{
            PartitionKey   = $Task.PartitionKey
            RowKey         = $Task.RowKey
            Acknowledged   = $true
            AcknowledgedBy = [string]$AcknowledgedBy
            AcknowledgedAt = [string][int64](([datetime]::UtcNow) - (Get-Date '1/1/1970')).TotalSeconds
        }

        $Result = "Acknowledged task '$($Task.Name)'. It will no longer appear in the needs-attention view unless it fails again."
        Write-LogMessage -headers $Headers -API $APIName -message $Result -Sev 'Info'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = $Result }
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Failed to acknowledge task: $($ErrorMessage.NormalizedError)" -Sev 'Error'
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = "Failed to acknowledge task: $($ErrorMessage.NormalizedError)" }
            })
    }
}
