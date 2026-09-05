function Invoke-ExecGetBecReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Server-renders the BEC (Business Email Compromise) analysis report as application/pdf bytes. Reads
        the cached BEC run for the user (the cachebec table, populated by execBECCheck / Push-BECRun) and
        composes it through the shared CIPPSharp component kit (Build-CippBecReportTree) - the server-side
        replacement for the client react-pdf BECRemediationReportButton. The BEC check must have completed
        for the user first (the report reads its cached result, it does not trigger a new run).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName
    Write-LogMessage -Headers $Request.Headers -API $APIName -message 'Accessed this API' -Sev 'Debug'

    try {
        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        $UserId = $Request.Query.userId ?? $Request.Query.userid ?? $Request.Query.GUID ?? $Request.Body.userId
        $UserName = $Request.Query.userName ?? $Request.Query.username ?? $Request.Body.userName
        $UserDisplayName = $Request.Query.userDisplayName ?? $Request.Body.userDisplayName
        if ([string]::IsNullOrWhiteSpace($TenantFilter) -or [string]::IsNullOrWhiteSpace($UserId)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'A tenantFilter and userId are required' })
        }

        # Read the cached BEC result (the same cache execBECCheck polls). No -Property projection so a result
        # split across part rows is reassembled.
        $Table = Get-CippTable -tablename 'cachebec'
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'bec' and RowKey eq '$UserId'" | Select-Object -First 1
        if (-not $Row -or [string]::IsNullOrEmpty($Row.Results) -or $Row.Status -eq 'Waiting') {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = 'No completed BEC analysis is cached for this user. Run the BEC check first, then generate the report.'
                })
        }

        $BecData = if ($Row.Results -is [string]) { $Row.Results | ConvertFrom-Json -AsHashtable } else { $Row.Results }

        $TenantName = $TenantFilter
        try {
            $TenantInfo = Get-Tenants -TenantFilter $TenantFilter
            if ($TenantInfo.displayName) { $TenantName = [string]$TenantInfo.displayName }
        } catch { $TenantName = $TenantFilter }

        $DisplayName = if (-not [string]::IsNullOrWhiteSpace($UserDisplayName)) { $UserDisplayName } elseif (-not [string]::IsNullOrWhiteSpace($UserName)) { $UserName } else { $UserId }
        $UserData = @{ displayName = $DisplayName; userPrincipalName = $UserName }

        $Tree = Build-CippBecReportTree -UserData $UserData -BecData $BecData -TenantName $TenantName

        $AnalysisDate = try { ([datetime]$BecData.ExtractedAt).ToString('MMM d, yyyy, hh:mm tt', [Globalization.CultureInfo]::InvariantCulture) } catch { [string]$BecData.ExtractedAt }
        $Variables = @{
            coverlabel      = 'Security Incident Report'
            covertitle      = 'BEC Compromise'
            coveraccent     = 'Analysis'
            covertenant     = $DisplayName
            coversubtitle   = "Business Email Compromise Investigation Report for $TenantName"
            covermeta       = [string]$UserName
            covermetanote   = "Analysis Date: $AnalysisDate"
            coverfallbackimage = '/reportImages/soc.jpg'
            coverfooternote = 'Confidential & Proprietary - For Internal Use Only'
            footerlabel     = "$TenantName - BEC Analysis Report for $DisplayName"
        }

        $Branding = try { Get-CIPPBrandingSettings } catch { @{} }
        $Bytes = ConvertTo-CippReportPdf -Blocks $Tree -Branding $Branding -Variables $Variables `
            -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'BEC Analysis Report' -GeneratedOn ((Get-Date).ToString('MMMM d, yyyy'))

        $FileName = ("BEC_Report_$DisplayName" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render BEC report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
