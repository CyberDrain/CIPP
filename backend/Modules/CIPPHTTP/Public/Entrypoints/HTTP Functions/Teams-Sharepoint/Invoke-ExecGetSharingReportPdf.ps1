function Invoke-ExecGetSharingReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Server-renders the SharePoint & OneDrive Sharing report as application/pdf bytes. Gathers the same
        shaped data the Sharing page uses (ListSharePointSharing, from the CIPP reporting cache), composes
        it through the shared CIPPSharp component kit (Build-CippSharingReportTree) and returns the finished
        PDF - the server-side replacement for the client react-pdf SharingReportButton.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -Headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'A tenantFilter is required' })
        }

        # Client display name for the cover; fall back to the tenant filter if it can't be resolved.
        $TenantName = $TenantFilter
        try {
            $TenantInfo = Get-Tenants -TenantFilter $TenantFilter
            if ($TenantInfo.displayName) { $TenantName = [string]$TenantInfo.displayName }
        } catch { $TenantName = $TenantFilter }

        # Gather the shaped sharing data in-process from the list endpoint (reads the reporting cache; no
        # live Graph enumeration), then hand it to the tree builder as a hashtable with the tenant name.
        $Raw = (Invoke-ListSharePointSharing -Request @{ Query = @{ tenantFilter = $TenantFilter }; Headers = $Request.Headers }).Body
        $Summary = $Raw.summary
        $Data = @{
            TenantName    = $TenantName
            summary       = $Summary
            links         = $Raw.links
            topRecipients = $Raw.topRecipients
            topLibraries  = $Raw.topLibraries
        }
        $Tree = Build-CippSharingReportTree -Data $Data

        # Cover / footer text (report variables). The exposure grade mirrors the tree's own grading so the
        # cover note and the in-report alert agree.
        function nz($v) { if ($null -eq $v) { 0 } else { [int]$v } }
        $Score = 0
        if ((nz $Summary.anonymousEditLinks) -gt 0) { $Score += 5 }
        if ((nz $Summary.neverExpiringAnonymous) -gt 0) { $Score += 3 }
        if ((nz $Summary.anonymousLinks) -gt 0) { $Score += 2 }
        if ((nz $Summary.folderShares) -gt 0) { $Score += 2 }
        if ((nz $Summary.externalLinks) -gt 0) { $Score += 1 }
        $Exposure = if ($Score -ge 7) { 'High' } elseif ($Score -ge 3) { 'Medium' } else { 'Low' }
        $Variables = @{
            coverlabel      = 'Data Sharing Review'
            coversubtitle   = "What has been shared out of SharePoint and OneDrive at $TenantName, who it reaches, and which of those shares are worth acting on."
            covermeta       = ('{0} sharing links / {1} items / {2} external recipients' -f (nz $Summary.totalLinks), (nz $Summary.itemsShared), (nz $Summary.externalRecipients))
            covermetanote   = "Sharing exposure: $Exposure"
            coverfooternote = 'Confidential - For Internal Use Only'
            coverfallbackimage = '/reportImages/glasses.jpg'
            footerlabel     = "$TenantName - SharePoint & OneDrive Sharing"
        }

        $Branding = try { Get-CIPPBrandingSettings } catch { @{} }
        $Bytes = ConvertTo-CippReportPdf -Blocks $Tree -Branding $Branding -Variables $Variables `
            -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Sharing Report' -GeneratedOn ((Get-Date).ToString('MMMM d, yyyy'))

        $FileName = ("Sharing_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render Sharing report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
