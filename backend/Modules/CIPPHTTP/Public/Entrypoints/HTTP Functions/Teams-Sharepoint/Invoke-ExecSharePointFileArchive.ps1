function Invoke-ExecSharePointFileArchive {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .SYNOPSIS
        Archive or reactivate a SharePoint file or folder with Microsoft 365 Archive.
    .DESCRIPTION
        Moves a file, or the eligible files in a folder, in a SharePoint document library to Microsoft 365 Archive
        storage, or reactivates it. Archived files stay listed in the library but cannot be opened until they are
        reactivated. A folder is processed in the background by Microsoft 365.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Id of the drive (document library) that holds the item.
    $DriveId = $Request.Body.DriveId
    # Id of the file or folder.
    $ItemId = $Request.Body.ItemId
    # Name of the file or folder, used in the result and the log.
    $ItemName = $Request.Body.ItemName ?? $ItemId
    # Set when the item is a folder.
    $IsFolder = $Request.Body.IsFolder -eq $true
    # Archive moves the item to Microsoft 365 Archive, Reactivate brings it back.
    $Action = $Request.Body.Action

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter is required.' } })
    }
    if ([string]::IsNullOrWhiteSpace($DriveId)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'DriveId is required.' } })
    }
    if ([string]::IsNullOrWhiteSpace($ItemId)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ItemId is required.' } })
    }
    if ([string]$DriveId -notmatch '^[A-Za-z0-9!_-]+$' -or [string]$ItemId -notmatch '^[A-Za-z0-9!_-]+$') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'DriveId and ItemId must be the ids of a drive and of a file or folder in it.' } })
    }
    if ([string]::IsNullOrWhiteSpace($Action)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Action is required.' } })
    }
    switch ($Action) {
        'Archive' { $Operation = 'archive' }
        'Reactivate' { $Operation = 'unarchive' }
        default {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Action must be Archive or Reactivate.' } })
        }
    }

    # The Graph write helper returns nothing for a tenant CIPP cannot reach, which would read as a successful archive.
    if (-not (Get-Tenants -TenantFilter $TenantFilter)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = "CIPP does not manage the tenant '$TenantFilter', or it is excluded. Select a managed tenant and try again." } })
    }

    try {
        $Uri = "https://graph.microsoft.com/beta/drives/$DriveId/items/$ItemId/$Operation"
        if ($IsFolder) {
            # Microsoft Graph only accepts a folder as a background request.
            $null = New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -AsApp $true -type POST -body '' -AddedHeaders @{ Prefer = 'respond-async' }
            $Result = if ($Operation -eq 'archive') {
                "Started archiving the eligible files in $ItemName. Microsoft 365 works through the folder in the background, so large folders take a while to finish."
            } else {
                "Started reactivating the files in $ItemName. Files archived in the last 7 days come back straight away, older files can take up to 24 hours."
            }
            $StatusCode = [HttpStatusCode]::Accepted
        } else {
            $Response = New-GraphPOSTRequest -uri $Uri -tenantid $TenantFilter -AsApp $true -type POST -body ''
            $Result = if ($Operation -eq 'archive') {
                "Archived $ItemName. It stays listed in the library but cannot be opened until it is reactivated."
            } elseif ($Response.file.archiveStatus -eq 'reactivating') {
                "Started reactivating $ItemName. This can take up to 24 hours."
            } else {
                "Reactivated $ItemName. It can be opened again now."
            }
            $StatusCode = [HttpStatusCode]::OK
        }
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Info
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to $("$Action".ToLower()) $($ItemName): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
