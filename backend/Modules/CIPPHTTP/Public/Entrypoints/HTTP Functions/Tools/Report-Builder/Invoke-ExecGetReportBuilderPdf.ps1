function Invoke-ExecGetReportBuilderPdf {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.Core.Read
    .DESCRIPTION
        Returns the server-rendered PDF for a generated Report Builder report as application/pdf bytes.
        Backs both the in-app preview (shown in an iframe) and the download button on the view and
        generated-reports pages.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $ReportGUID = $Request.Query.id ?? $Request.Query.ReportGUID
        if ([string]::IsNullOrEmpty($ReportGUID)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = 'A report id is required'
                })
        }

        $ReportGUID = ConvertTo-CIPPODataFilterValue -Value $ReportGUID -Type 'Guid'
        $Table = Get-CippTable -tablename 'ReportBuilderReports'
        # No -Property projection: the merge-aware read reassembles a PDF that was split across part rows.
        $Report = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$ReportGUID'" | Select-Object -First 1

        if (-not $Report) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = 'Report not found'
                })
        }
        if ([string]::IsNullOrEmpty($Report.Pdf)) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = 'This report has no rendered PDF. Regenerate it to produce one.'
                })
        }

        $Bytes = [Convert]::FromBase64String($Report.Pdf)
        $FileName = ("$($Report.TemplateName)_$($Report.TenantFilter)" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'

        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -user $Request.Headers.'x-ms-client-principal' -API $APIName -message "Failed to fetch report PDF: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = "Error: $($ErrorMessage.NormalizedError)"
            })
    }
}
