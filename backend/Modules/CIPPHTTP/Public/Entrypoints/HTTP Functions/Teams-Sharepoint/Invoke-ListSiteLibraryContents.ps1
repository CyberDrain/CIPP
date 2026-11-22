function Invoke-ListSiteLibraryContents {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .SYNOPSIS
        List the folders and files in a SharePoint document library with their sizes.
    .DESCRIPTION
        Lists one folder of a SharePoint document library with the size, last change and Microsoft 365 Archive status
        of every folder and file in it, so the items using the most storage can be found by opening the largest folder
        at each level. With LargestFiles it returns the largest files anywhere below that folder instead, along with
        any large folders that were too deep to search, so the search can be repeated inside them.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter
    # Graph id of the site that holds the library. Send this or SiteUrl.
    $SiteId = $Request.Query.SiteId
    # Web address of the site that holds the library. Send this or SiteId.
    $SiteUrl = $Request.Query.SiteUrl
    # Id of the document library (its list id).
    $ListId = $Request.Query.ListId
    # Id of the folder to list. The top of the library is listed when this is left out.
    $FolderId = $Request.Query.FolderId
    # Return the largest files anywhere below the folder instead of the folder's own contents.
    $LargestFiles = $Request.Query.LargestFiles -eq $true

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter is required.' } })
    }
    if ($TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'A library is listed one tenant at a time. Select a single tenant.' } })
    }
    if ([string]::IsNullOrWhiteSpace($ListId)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ListId is required.' } })
    }
    if (-not [guid]::TryParse([string]$ListId, [ref][guid]::Empty)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'ListId must be the id of a document library.' } })
    }
    if ([string]::IsNullOrWhiteSpace($SiteId) -and [string]::IsNullOrWhiteSpace($SiteUrl)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'SiteId or SiteUrl is required.' } })
    }
    if (-not [string]::IsNullOrWhiteSpace($FolderId) -and [string]$FolderId -notmatch '^[A-Za-z0-9!_-]+$') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'FolderId is not a valid folder id.' } })
    }
    if (-not [string]::IsNullOrWhiteSpace($SiteId)) {
        if ([string]$SiteId -notmatch '^[A-Za-z0-9.,-]+$') {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'SiteId is not a valid site id.' } })
        }
        $SiteSegment = [string]$SiteId
    } else {
        $ParsedUrl = $null
        if (-not [System.Uri]::TryCreate([string]$SiteUrl, [System.UriKind]::Absolute, [ref]$ParsedUrl) -or [string]::IsNullOrWhiteSpace($ParsedUrl.Host)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "SiteUrl '$SiteUrl' is not a valid URL." } })
        }
        $SiteSegment = if ($ParsedUrl.AbsolutePath -in @('', '/')) { $ParsedUrl.Host } else { "$($ParsedUrl.Host):$($ParsedUrl.AbsolutePath.TrimEnd('/')):" }
    }

    try {
        $Results = Get-CIPPSharePointLibraryContents -TenantFilter $TenantFilter -SiteSegment $SiteSegment -ListId $ListId -FolderId $FolderId -LargestFiles:$LargestFiles
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to list the library contents: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}
