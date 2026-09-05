function Invoke-ExecGetShadowAIReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    .DESCRIPTION
        Server-renders the Shadow AI report as application/pdf bytes. Gathers the same shaped data the
        Shadow AI page uses (ListShadowAI) and composes it through the shared CIPPSharp component kit
        (Build-CippShadowAIReportTree) - the server-side replacement for the client react-pdf
        ShadowAIReportButton.
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

        $Raw = (Invoke-ListShadowAI -Request @{ Query = @{ tenantFilter = $TenantFilter }; Headers = $Request.Headers }).Body
        $Data = @{
            TenantName    = $TenantName
            summary       = $Raw.summary
            detectedApps  = $Raw.detectedApps
            consentedApps = $Raw.consentedApps
            topTools      = $Raw.topTools
            byRisk        = $Raw.byRisk
        }

        # Optional per-section toggles from the client's section panel (POST body). Absent -> full report.
        $SectionConfig = @{}
        $RawCfg = $Request.Body.sectionConfig ?? $Request.Body.SectionConfig
        if ($RawCfg) {
            if ($RawCfg -is [hashtable]) { $SectionConfig = $RawCfg }
            else { foreach ($p in $RawCfg.PSObject.Properties) { $SectionConfig[$p.Name] = [bool]$p.Value } }
        }

        # Section-divider photos ship beside the CIPPSharp assembly; the renderer resolves the
        # /reportImages/ paths to the bundled bytes, so the hero pages render with their photos.
        $Tree = Build-CippShadowAIReportTree -Data $Data -HeroImages (Get-CippReportHeroImages) -SectionConfig $SectionConfig

        $Variables = @{
            coverlabel      = 'AI Risk Assessment'
            coversubtitle   = 'Discovery and risk assessment of AI tools in use across managed devices and cloud applications.'
            coverfooternote = 'Confidential - For Internal Use Only'
            coverfallbackimage = '/reportImages/city.jpg'
            footerlabel     = "$TenantName - Shadow AI Report"
        }

        $Branding = try { Get-CIPPBrandingSettings } catch { @{} }
        $Bytes = ConvertTo-CippReportPdf -Blocks $Tree -Branding $Branding -Variables $Variables `
            -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Shadow AI Report' -GeneratedOn ((Get-Date).ToString('MMMM d, yyyy'))

        $FileName = ("Shadow_AI_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render Shadow AI report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
