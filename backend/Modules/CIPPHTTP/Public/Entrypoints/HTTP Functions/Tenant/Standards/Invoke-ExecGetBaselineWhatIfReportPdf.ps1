function Invoke-ExecGetBaselineWhatIfReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Baselines.Read
    .DESCRIPTION
        Server-renders the Baseline What-If report as application/pdf bytes: what applying the
        configured standards would change for a tenant today, what each planned stage will change,
        optionally what assigning one more baseline would roll out, and the agreed exceptions. Reads
        the same alignment payload the Baselines page shows (Get-CIPPBaselineAlignment), composes it
        through the shared CIPPSharp component kit (Build-CippBaselineWhatIfReportTree) and returns
        the finished PDF. Nothing is changed by producing it.
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
        # Optional: the GUID of a baseline not assigned to the tenant, to preview what assigning it would roll out stage by stage.
        $SimulatedTemplateId = [string]($Request.Query.simulatedTemplateId ?? $Request.Body.simulatedTemplateId)
        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter

        $Alignment = Get-CIPPBaselineAlignment -TenantFilter $TenantFilter
        $Simulated = if ($SimulatedTemplateId) { @(Get-CIPPBaseline) | Where-Object { $_.GUID -eq $SimulatedTemplateId } | Select-Object -First 1 }
        $Report = Build-CippBaselineWhatIfReportTree -Data @{
            TenantName        = $TenantName
            TenantFilter      = $TenantFilter
            summary           = $Alignment.summary
            rows              = @($Alignment.rows)
            stageStates       = @($Alignment.stageStates)
            simulatedTemplate = $Simulated
            catalog           = @(Get-CIPPBaselineDefinition)
        }

        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Baseline What-If Report'
        $FileName = ("Baseline_WhatIf_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render the Baseline What-If report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
