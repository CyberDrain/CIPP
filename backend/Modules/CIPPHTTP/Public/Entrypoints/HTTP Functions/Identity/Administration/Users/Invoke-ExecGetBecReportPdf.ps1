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
        # The investigated user's object id (the cachebec RowKey).
        $UserId = $Request.Query.userId ?? $Request.Body.userId
        if ([string]::IsNullOrWhiteSpace($TenantFilter) -or [string]::IsNullOrWhiteSpace($UserId)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'A tenantFilter and userId are required' })
        }

        # Read the cached BEC result (the same cache execBECCheck polls). No -Property projection so a result
        # split across part rows is reassembled.
        $Table = Get-CippTable -tablename 'cachebec'
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'bec' and RowKey eq '$UserId'" | Select-Object -First 1
        if ([string]::IsNullOrEmpty($Row.Results) -or $Row.Status -eq 'Waiting') {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = 'No completed BEC analysis is cached for this user. Run the BEC check first, then generate the report.'
                })
        }
        $BecData = $Row.Results | ConvertFrom-Json -AsHashtable

        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter
        # The investigated user's UPN and display name label the cover and footer.
        $UserName = $Request.Query.userName ?? $Request.Body.userName
        $DisplayName = @($Request.Query.userDisplayName, $Request.Body.userDisplayName, $UserName, $UserId) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First 1

        $Report = Build-CippBecReportTree -UserData @{ displayName = $DisplayName; userPrincipalName = $UserName } -BecData $BecData -TenantName $TenantName

        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'BEC Analysis Report'
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
