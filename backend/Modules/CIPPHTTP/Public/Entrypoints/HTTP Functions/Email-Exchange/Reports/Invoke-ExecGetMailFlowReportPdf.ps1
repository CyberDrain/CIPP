function Invoke-ExecGetMailFlowReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Server-renders the Exchange mail flow report as application/pdf bytes. Gathers the same three mail
        flow datasets the Mail Flow page uses (ListMailFlowReports: MailFlowStatus, TopMailSender,
        TopSpamRecipient), aggregates the daily disposition rows the way the page does, and composes them
        through the shared CIPPSharp kit (Build-CippMailFlowReportTree) - the server-side replacement for the
        client react-pdf MailFlowReportButton.
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
        $Days = [Math]::Min([Math]::Max([int]($Request.Query.days ?? 14), 1), 90)

        $TenantName = $TenantFilter
        try {
            $TenantInfo = Get-Tenants -TenantFilter $TenantFilter
            if ($TenantInfo.displayName) { $TenantName = [string]$TenantInfo.displayName }
        } catch { $TenantName = $TenantFilter }

        # Gather the three datasets in-process (each reads Exchange Online via the list endpoint).
        function Invoke-Report($ReportType, $Category) {
            $Query = @{ tenantFilter = $TenantFilter; reportType = $ReportType; days = $Days }
            if ($Category) { $Query.category = $Category }
            (Invoke-ListMailFlowReports -Request @{ Query = $Query; Headers = $Request.Headers; Params = @{ CIPPEndpoint = 'ListMailFlowReports' } }).Body.Results
        }
        $FlowRows = @(Invoke-Report 'MailFlowStatus' $null)
        $TopSenders = @(Invoke-Report 'TrafficSummary' 'TopMailSender')
        $TopSpam = @(Invoke-Report 'TrafficSummary' 'TopSpamRecipient')

        # Aggregate the daily disposition rows (port of the page's useMemo): sum Count per date+EventType,
        # per EventType, and per Direction.
        $EventKeys = @('GoodMail', 'TransportRules', 'SpamDetections', 'EdgeBlockSpam', 'EmailPhish', 'EmailMalware')
        $ByDateType = @{}
        $TypeTotals = @{}
        $Dir = @{ Inbound = 0.0; Outbound = 0.0; IntraOrg = 0.0 }
        $Dates = @($FlowRows | ForEach-Object { [string]$_.Date } | Sort-Object -Unique)
        foreach ($Row in $FlowRows) {
            $Count = 0.0; [void][double]::TryParse("$($Row.Count)", [ref]$Count)
            $EventType = [string]$Row.EventType
            $DateKey = "$([string]$Row.Date)|$EventType"
            $ByDateType[$DateKey] = ($(if ($ByDateType.ContainsKey($DateKey)) { $ByDateType[$DateKey] } else { 0.0 })) + $Count
            $TypeTotals[$EventType] = ($(if ($TypeTotals.ContainsKey($EventType)) { $TypeTotals[$EventType] } else { 0.0 })) + $Count
            $Direction = [string]$Row.Direction
            if ($Dir.ContainsKey($Direction)) { $Dir[$Direction] += $Count }
        }
        $Totals = @{}
        foreach ($k in $EventKeys) { $Totals[$k] = if ($TypeTotals.ContainsKey($k)) { $TypeTotals[$k] } else { 0 } }
        $Daily = @($Dates | ForEach-Object {
                $Date = $_
                $DayRow = @{ date = $Date }
                foreach ($k in $EventKeys) { $Key = "$Date|$k"; $DayRow[$k] = if ($ByDateType.ContainsKey($Key)) { $ByDateType[$Key] } else { 0 } }
                $DayRow
            })

        $Data = @{
            TenantName        = $TenantName
            days              = $Days
            totals            = $Totals
            directionTotals   = $Dir
            daily             = $Daily
            topSenders        = $TopSenders
            topSpamRecipients = $TopSpam
        }
        $Tree = Build-CippMailFlowReportTree -Data $Data

        # Cover / footer text (report variables). Total, delivered % and threats mirror the tree's own
        # figures, and the hygiene grade uses the tree's thresholds so the cover note and the alert agree.
        function pctOf($p, $w) { if ($w -gt 0) { [math]::Round(($p / $w) * 1000) / 10 } else { 0 } }
        $TotalMail = 0.0; foreach ($k in $EventKeys) { $TotalMail += $Totals[$k] }
        $GoodPct = pctOf $Totals.GoodMail $TotalMail
        $Threats = $Totals.EmailPhish + $Totals.EmailMalware
        $Targeted = pctOf ($Totals.EmailMalware + $Totals.EmailPhish) $TotalMail
        $SpamPct = pctOf ($Totals.SpamDetections + $Totals.EdgeBlockSpam) $TotalMail
        $Hygiene = if ($TotalMail -le 0) { 'Good' } elseif ($Targeted -gt 1 -or $SpamPct -gt 25) { 'Attention Needed' } elseif ($Targeted -gt 0.25 -or $SpamPct -gt 10) { 'Fair' } else { 'Good' }
        $Variables = @{
            coverlabel      = 'Email Traffic Review'
            coversubtitle   = "Where email at $TenantName came from over the last $Days days, how much of it was delivered, and what was stopped before it reached a mailbox."
            covermeta       = ('{0:N0} messages / {1}% delivered / {2:N0} threats caught' -f $TotalMail, $GoodPct, $Threats)
            covermetanote   = "Mail hygiene: $Hygiene"
            coverfooternote = 'Confidential - For Internal Use Only'
            coverfallbackimage = '/reportImages/city.jpg'
            footerlabel     = "$TenantName - Mail Flow"
        }

        $Branding = try { Get-CIPPBrandingSettings } catch { @{} }
        $Bytes = ConvertTo-CippReportPdf -Blocks $Tree -Branding $Branding -Variables $Variables `
            -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Mail Flow Report' -GeneratedOn ((Get-Date).ToString('MMMM d, yyyy'))

        $FileName = ("Mail_Flow_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render Mail Flow report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
