function Invoke-ExecArchiveSite {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.ReadWrite
    .SYNOPSIS
        Archive a whole SharePoint site with Microsoft 365 Archive.
    .DESCRIPTION
        Moves a SharePoint site into Microsoft 365 Archive. Nobody can open the site or its files until it is
        reactivated, which is instant for the first 7 days and can take up to 24 hours after that. The site stops
        counting towards SharePoint storage. Hub sites must be unregistered first, and private or shared channel
        sites of a team are not archived with it.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Body.tenantFilter
    # Full web address of the site (the row's webUrl).
    $SiteUrl = $Request.Body.SiteUrl
    # Site collection id (the row's siteId). With WebId it saves a lookup of the site.
    $SiteId = $Request.Body.SiteId
    # Web id (the row's webId).
    $WebId = $Request.Body.WebId

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter is required.' } })
    }
    if ([string]::IsNullOrWhiteSpace($SiteUrl)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'SiteUrl is required.' } })
    }
    $ParsedSiteUrl = $null
    if (-not [System.Uri]::TryCreate([string]$SiteUrl, [System.UriKind]::Absolute, [ref]$ParsedSiteUrl) -or [string]::IsNullOrWhiteSpace($ParsedSiteUrl.Host)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "SiteUrl '$SiteUrl' is not a valid URL." } })
    }
    $SiteGuid = [guid]::Empty
    $WebGuid = [guid]::Empty
    $HasIds = [guid]::TryParse(([string]$SiteId).Trim('{}'), [ref]$SiteGuid) -and [guid]::TryParse(([string]$WebId).Trim('{}'), [ref]$WebGuid)

    # The Graph write helper returns nothing for a tenant CIPP cannot reach, which would read as a successful archive.
    if (-not (Get-Tenants -TenantFilter $TenantFilter)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = "CIPP does not manage the tenant '$TenantFilter', or it is excluded. Select a managed tenant and try again." } })
    }

    try {
        if ($HasIds) {
            $GraphSiteId = '{0},{1},{2}' -f $ParsedSiteUrl.Host, $SiteGuid, $WebGuid
        } else {
            $SitePath = if ($ParsedSiteUrl.AbsolutePath -in @('', '/')) { $ParsedSiteUrl.Host } else { "$($ParsedSiteUrl.Host):$($ParsedSiteUrl.AbsolutePath.TrimEnd('/'))" }
            $GraphSiteId = (New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/sites/$SitePath`?`$select=id" -tenantid $TenantFilter -AsApp $true -ErrorAction Stop).id
            if ([string]::IsNullOrWhiteSpace($GraphSiteId)) {
                throw [System.Management.Automation.ItemNotFoundException]::new("The site $SiteUrl was not found.")
            }
        }

        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/beta/sites/$GraphSiteId/archive" -tenantid $TenantFilter -AsApp $true -type POST -body ''

        $Results = "Archiving started for $SiteUrl. Nobody can open the site until it is reactivated: that is instant for the first 7 days and can take up to 24 hours after that."
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Info
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to archive $($SiteUrl): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Results }
        })
}
