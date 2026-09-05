function Invoke-ExecGetPermissionsReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Server-renders the SharePoint Permissions report as application/pdf bytes. Gathers the same shaped
        data the Permissions page uses (ListSharePointPermissions, from the CIPP reporting cache), composes
        it through the shared CIPPSharp component kit (Build-CippPermissionsReportTree) and returns the
        finished PDF - the server-side replacement for the client react-pdf PermissionsReportButton.
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

        $TenantName = $TenantFilter
        try {
            $TenantInfo = Get-Tenants -TenantFilter $TenantFilter
            if ($TenantInfo.displayName) { $TenantName = [string]$TenantInfo.displayName }
        } catch { $TenantName = $TenantFilter }

        $Raw = (Invoke-ListSharePointPermissions -Request @{ Query = @{ tenantFilter = $TenantFilter }; Headers = $Request.Headers }).Body
        $Summary = $Raw.summary
        $Data = @{
            TenantName   = $TenantName
            summary      = $Summary
            assignments  = $Raw.assignments
            skippedSites = $Raw.skippedSites
        }
        $Tree = Build-CippPermissionsReportTree -Data $Data

        function nz($v) { if ($null -eq $v) { 0 } else { [int]$v } }
        $Score = 0
        if ((nz $Summary.broadClaimGrants) -gt 0) { $Score += 5 }
        if ((nz $Summary.externalGrants) -gt 0) { $Score += 3 }
        if ((nz $Summary.directFullControlGrants) -gt 0) { $Score += 2 }
        if ((nz $Summary.uniquePermissionLibraries) -gt 0) { $Score += 1 }
        $Exposure = if ($Score -ge 7) { 'High' } elseif ($Score -ge 3) { 'Medium' } else { 'Low' }
        $Variables = @{
            coverlabel      = 'Access Review'
            coversubtitle   = "Who is structurally allowed into SharePoint sites and document libraries at $TenantName, and where that access reaches further than intended."
            covermeta       = ('{0} sites / {1} libraries / {2} permission assignments' -f (nz $Summary.sitesScanned), (nz $Summary.librariesScanned), (nz $Summary.totalAssignments))
            covermetanote   = "Permission exposure: $Exposure"
            coverfooternote = 'Confidential - For Internal Use Only'
            coverfallbackimage = '/reportImages/soc.jpg'
            footerlabel     = "$TenantName - SharePoint Permissions"
        }

        $Branding = try { Get-CIPPBrandingSettings } catch { @{} }
        $Bytes = ConvertTo-CippReportPdf -Blocks $Tree -Branding $Branding -Variables $Variables `
            -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Permissions Report' -GeneratedOn ((Get-Date).ToString('MMMM d, yyyy'))

        $FileName = ("Permissions_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render Permissions report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
