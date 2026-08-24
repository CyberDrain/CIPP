function Invoke-ListBECEvidence {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .SYNOPSIS
        Builds and downloads the evidence package of a Business Email Compromise run.
    .DESCRIPTION
        With download=true, collates the run's stored results, containment history and case logbook into a fresh ZIP with a SHA-256 manifest and streams it as application/zip; nothing is stored - the export is recorded on the run (hash, time, size) so the download can be verified later. This path cannot include the PDF report, which only the browser can render; ExecBECEvidenceExport accepts one. Without download=true the run's recorded exports are returned instead.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $TenantFilter = $Request.Query.tenantFilter
    $CaseId = [string]$Request.Query.caseId
    # true builds and streams the ZIP; otherwise the run's recorded exports are returned
    $Download = $Request.Query.download -eq $true

    try {
        if (-not $TenantFilter -or -not $CaseId) { throw 'tenantFilter and caseId are required' }
        if (-not $Download) {
            $Run = Get-CIPPBecReport -TenantFilter $TenantFilter -CaseId $CaseId
            if (-not $Run) { throw "BEC run $CaseId was not found for $TenantFilter" }
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = [pscustomobject]@{
                        CaseId            = $CaseId
                        EvidenceSha256    = $Run.EvidenceSha256
                        EvidenceCreatedAt = $Run.EvidenceCreatedAt
                        EvidenceBytes     = $Run.EvidenceBytes
                        Exports           = @($Run.EvidenceExports)
                    }
                })
        }
        Set-CippBecCaseContext -CaseId $CaseId
        try {
            $Package = New-CIPPBecEvidencePackage -TenantFilter $TenantFilter -CaseId $CaseId -Headers $Headers -APIName $APIName
        } finally {
            Set-CippBecCaseContext -CaseId $null
        }
        # Stream the raw bytes (Craft streams a byte[] Body verbatim); Content-Disposition names the
        # file for the browser so it saves as the case, not the endpoint name. This server path cannot
        # include the report PDFs - only the browser can render those, so use ExecBECEvidenceExport for
        # a package with the report.
        $FileName = "BEC_Evidence_$($CaseId -replace '[^A-Za-z0-9._-]+', '_').zip"
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/zip'
                Headers     = @{ 'Content-Disposition' = "attachment; filename=`"$FileName`"" }
                Body        = [byte[]]$Package.ZipBytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::InternalServerError
                Body       = @{ Results = "Evidence download failed: $($ErrorMessage.NormalizedError)" }
            })
    }
}
