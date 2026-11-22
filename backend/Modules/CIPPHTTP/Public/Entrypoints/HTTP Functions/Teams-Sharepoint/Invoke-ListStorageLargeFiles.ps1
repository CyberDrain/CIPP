function Invoke-ListStorageLargeFiles {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .SYNOPSIS
        List the largest files found by the SharePoint large file scan.
    .DESCRIPTION
        Returns the largest files in each SharePoint site of a tenant, with their size, location, last change and
        Microsoft 365 Archive status, from the last large file scan. Nothing is read live: start a scan with
        ExecSharePointStorageSync Name=StorageLargeFiles.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter is required.' } })
    }
    if ($TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'The large file scan is read one tenant at a time. Select a single tenant.' } })
    }

    try {
        # The count row is written by every scan, including one that found nothing.
        $Scanned = $false
        $Results = foreach ($Row in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'StorageLargeFiles' -TableName 'CippStorageLargeFiles')) {
            if ($Row.RowKey -eq 'StorageLargeFiles-Count') {
                $Scanned = $true
                continue
            }
            $Parsed = try { [CIPP.CippJson]::ConvertFromJson($Row.Data, $null) } catch { continue }
            foreach ($Record in @($Parsed)) {
                if ($Record.rowType -eq 'File') { $Record }
            }
        }
        if (-not $Scanned) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = 'No large file scan has run for this tenant yet. Use Scan large files on the Storage Report to start one.' } })
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to read the large file scan: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}
