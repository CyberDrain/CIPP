function Invoke-ExecBulkActionConfirmConfig {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    .DESCRIPTION
        Reads or saves the global bulk-action confirmation countdown setting: whether the
        confirm button on bulk actions is gated behind a countdown once the selection exceeds
        a configurable item threshold. Disabled by default.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    $Table = Get-CIPPTable -TableName Config
    $Filter = "PartitionKey eq 'BulkActionConfirm' and RowKey eq 'Settings'"

    $Results = try {
        if ($Request.Query.List) {
            $ConfirmSettings = Get-CIPPAzDataTableEntity @Table -Filter $Filter
            if (!$ConfirmSettings) {
                # Return default values if not set
                @{
                    Enabled          = $false
                    Threshold        = 10
                    CountdownSeconds = 5
                }
            } else {
                @{
                    Enabled          = [bool]$ConfirmSettings.Enabled
                    Threshold        = if ([int]::TryParse("$($ConfirmSettings.Threshold)", [ref]$null)) { [int]$ConfirmSettings.Threshold } else { 10 }
                    CountdownSeconds = if ([int]::TryParse("$($ConfirmSettings.CountdownSeconds)", [ref]$null)) { [int]$ConfirmSettings.CountdownSeconds } else { 5 }
                }
            }
        } else {
            $Enabled = [bool]$Request.Body.Enabled

            $Threshold = 0
            if (-not [int]::TryParse("$($Request.Body.Threshold)", [ref]$Threshold) -or $Threshold -lt 1) {
                throw 'Item threshold must be a whole number of at least 1'
            }

            $CountdownSeconds = 0
            if (-not [int]::TryParse("$($Request.Body.CountdownSeconds)", [ref]$CountdownSeconds) -or $CountdownSeconds -lt 1 -or $CountdownSeconds -gt 60) {
                throw 'Countdown seconds must be a whole number between 1 and 60'
            }

            $ConfirmConfig = @{
                'PartitionKey'     = 'BulkActionConfirm'
                'RowKey'           = 'Settings'
                'Enabled'          = $Enabled
                'Threshold'        = $Threshold
                'CountdownSeconds' = $CountdownSeconds
            }

            Add-CIPPAzDataTableEntity @Table -Entity $ConfirmConfig -Force | Out-Null
            Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Set bulk action confirmation countdown: Enabled=$Enabled, Threshold=$Threshold, CountdownSeconds=$CountdownSeconds" -Sev 'Info'
            "Successfully set bulk action confirmation countdown"
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to set bulk action confirmation countdown: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        "Failed to set configuration: $($ErrorMessage.NormalizedError)"
    }

    $Body = [pscustomobject]@{'Results' = $Results }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}

