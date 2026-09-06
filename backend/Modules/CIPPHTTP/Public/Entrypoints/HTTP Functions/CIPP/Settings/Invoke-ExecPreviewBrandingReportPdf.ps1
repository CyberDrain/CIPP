function Invoke-ExecPreviewBrandingReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.Read
    .DESCRIPTION
        Renders a sample report against a branding configuration - normally the unsaved state of the
        branding editor - and returns it as application/pdf bytes, so a colour, logo, cover, footer or
        watermark can be judged on every page of a real report before it is saved. Each report type has
        a fixed sample of the data its builder needs (Config/ReportSamples/<type>.json); nothing is read
        from a tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -Headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    $ReportNames = @{
        executive = 'Executive Summary'; reportBuilder = 'Quarterly Security Review'; shadowAI = 'Shadow AI Report'
        bec = 'BEC Analysis Report'; sharing = 'Sharing Report'; permissions = 'Permissions Report'; mailFlow = 'Mail Flow Report'
    }

    try {
        # Which report to preview: executive, reportBuilder, shadowAI, bec, sharing, permissions or mailFlow.
        $ReportType = [string]($Request.Body.reportType ?? 'executive')
        if (-not $ReportNames.ContainsKey($ReportType)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = "Unknown report type '$ReportType'. Use one of: $($ReportNames.Keys -join ', ')." })
        }
        $Sample = Get-Content (Join-Path $env:CIPPRootPath "Config\ReportSamples\$ReportType.json") -Raw | ConvertFrom-Json -AsHashtable
        # The branding to render against, in the shape Get-CIPPBrandingSettings returns: colours (flat or
        # under roleColours), a data-URL logo and cover or a coverStock path, footer, watermark and
        # tenantLabel. Omitted -> the saved branding settings.
        $Branding = $Request.Body.branding
        # The sample tenant, named the way the branding under edit would name a real one.
        $TenantName = switch ([string]$Branding.tenantLabel) {
            'domain' { 'contoso.onmicrosoft.com' }
            'name' { 'Contoso Ltd (sample data)' }
            default { 'Contoso (sample data)' }
        }
        $Data = @{ TenantName = $TenantName } + $Sample
        $Report = switch ($ReportType) {
            'reportBuilder' { @{ Blocks = @($Sample.blocks); Variables = @{} } }
            'shadowAI' { Build-CippShadowAIReportTree -Data $Data }
            'bec' { Build-CippBecReportTree -UserData $Sample.userData -BecData $Sample.becData -TenantName $TenantName }
            'sharing' { Build-CippSharingReportTree -Data $Data }
            'permissions' { Build-CippPermissionsReportTree -Data $Data }
            'mailFlow' { Build-CippMailFlowReportTree -Data $Data }
            default { Build-CippExecutiveReportTree -Data $Data }
        }

        # Optional: the tenant whose %variables% (%cippurl%, custom variables) resolve in the footer and cover.
        $TenantFilter = [string]$Request.Body.tenantFilter
        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -Branding $Branding -TenantName $TenantName -TenantFilter $TenantFilter -ReportName $ReportNames[$ReportType]

        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = 'inline; filename="Branding_Preview.pdf"' }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render the branding preview: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
