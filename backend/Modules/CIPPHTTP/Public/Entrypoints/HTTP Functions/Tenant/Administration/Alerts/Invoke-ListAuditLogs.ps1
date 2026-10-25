function Invoke-ListAuditLogs {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.Read
    .DESCRIPTION
        Lists audit log entries from the CIPP audit log store, filterable by tenant, date range, and log ID. Kind=Threshold
        lists only repeated activity alerts (one user or app doing something a set number of times within a window);
        AlertType says which kind each entry is, and TimesRepeated how many times for a repeated activity alert.
        With manualPagination it returns one page at a time, with a Metadata.nextLink to pass back for the next page.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)
    # Interact with query parameters or the body of the request.
    $TenantFilter = ConvertTo-CIPPODataFilterValue -Value $Request.Query.tenantFilter -Type 'String'

    if ($Request.Query.LogId) {
        # A record's Id, or a threshold alert's 'threshold-<rule>-<identity>-<time>'.
        $LogID = ConvertTo-CIPPODataFilterValue -Value $Request.Query.LogId -Type 'String'
    }
    $StartDate = $Request.Query.StartDate
    $EndDate = $Request.Query.EndDate
    $RelativeTime = $Request.Query.RelativeTime
    $FilterConditions = [System.Collections.Generic.List[string]]::new()

    if ($LogID) {
        $FilterConditions.Add("RowKey eq '$($LogID)' or OriginalEntityId eq '$($LogID)'")
    } else {
        if ($TenantFilter -and $TenantFilter -ne 'AllTenants') {
            $FilterConditions.Add("Tenant eq '$TenantFilter'")
        }
        if ($Request.Query.Kind -eq 'Threshold') {
            $FilterConditions.Add("RowKey ge 'threshold-' and RowKey lt 'threshold.'")
        }

        if (!$StartDate -and !$EndDate -and !$RelativeTime) {
            $StartDate = (Get-Date).AddDays(-7).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            $EndDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        }

        if ($RelativeTime) {

            if ($RelativeTime -match '(\d+)([dhm])') {
                $EndDate = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                $Interval = [Int32]$Matches[1]
                switch ($Matches[2]) {
                    'd' { $StartDate = (Get-Date).AddDays(-$Interval).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
                    'h' { $StartDate = (Get-Date).AddHours(-$Interval).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
                    'm' { $StartDate = (Get-Date).AddMinutes(-$Interval).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
                }
            }
            $FilterConditions.Add("Timestamp ge datetime'$StartDate' and Timestamp le datetime'$EndDate'")
        } else {
            if ($StartDate) {
                if ($StartDate -match '^\d+$') {
                    $StartDate = [DateTimeOffset]::FromUnixTimeSeconds([int]$StartDate).DateTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                } else {
                    $StartDate = (Get-Date $StartDate).ToString('yyyy-MM-ddTHH:mm:ssZ')
                }
                $FilterConditions.Add("Timestamp ge datetime'$StartDate'")

                if ($EndDate) {
                    if ($EndDate -match '^\d+$') {
                        $EndDate = [DateTimeOffset]::FromUnixTimeSeconds([int]$EndDate).DateTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                    } else {
                        $EndDate = (Get-Date $EndDate).ToString('yyyy-MM-ddTHH:mm:ssZ')
                    }
                    $FilterConditions.Add("Timestamp le datetime'$EndDate'")
                }
            }
        }
    }

    $Table = Get-CIPPTable -TableName 'AuditLogs'
    $Tenants = Get-Tenants -IncludeErrors
    $Shape = {
        param($Row)
        $Data = try { $Row.Data | ConvertFrom-Json } catch { $Row.AuditData }
        $Raw = $Data.RawData
        [pscustomobject]@{
            LogId         = $Row.RowKey
            Timestamp     = $Raw.CreationTime
            Tenant        = $Row.Tenant
            Title         = $Row.Title
            AlertType     = if ($Row.RowKey -like 'threshold-*') { 'Repeated activity' } else { 'Single event' }
            Workload      = $Raw.Workload
            Operation     = $Raw.Operation
            User          = $Raw.UserId
            TimesRepeated = $Raw.CIPPThresholdCount
            Data          = $Data
        }
    }

    if (-not $LogID -and $Request.Query.manualPagination -eq $true) {
        # About five table pages of rows per response.
        $PageSize = 5000
        # The allowed tenants' partitions in a fixed order, each by RowKey: a resume point must follow this order, not the
        # order the store returns rows in (the storage emulator's differs).
        $Plan = [string[]]@($Tenants.defaultDomainName | Where-Object { $_ -and (-not $TenantFilter -or $TenantFilter -eq 'AllTenants' -or $_ -eq $TenantFilter) })
        [System.Array]::Sort($Plan, [System.StringComparer]::Ordinal)
        $At = 0
        $LastRowKey = $null
        # The previous page's Metadata.nextLink: '<tenant>|<last RowKey>'.
        if ($Request.Query.nextLink) {
            $Parts = ([string]$Request.Query.nextLink).Split('|', 2)
            $At = [System.Array]::IndexOf($Plan, $Parts[0])
            if ($At -lt 0) { $At = $Plan.Count }
            $LastRowKey = $Parts[1]
        }
        $Rows = [System.Collections.Generic.List[object]]::new()
        $Queries = 0
        # A bounded number of table queries per page, so many tenants without saved logs return a short page and a nextLink.
        while ($At -lt $Plan.Count -and $Queries -lt 25 -and $Rows.Count -lt $PageSize) {
            $Filter = @("PartitionKey eq '$(ConvertTo-CIPPODataFilterValue -Value $Plan[$At] -Type 'String')'") + @($FilterConditions)
            # '~' sorts after every character of these RowKeys, so this resumes after the last row and its split parts.
            if ($LastRowKey) { $Filter += "RowKey gt '$(ConvertTo-CIPPODataFilterValue -Value $LastRowKey -Type 'String')~'" }
            $Chunk = @(Get-CIPPAzDataTableEntity @Table -Filter ($Filter -join ' and ') -First ($PageSize - $Rows.Count))
            $Queries++
            if ($Chunk.Count -gt 0) {
                $LastRowKey = $Chunk[-1].RowKey
                foreach ($Row in $Chunk) { $Rows.Add((& $Shape $Row)) }
            } else {
                # -First counts physical rows before split rows are joined, so only an empty chunk ends a tenant.
                $At++
                $LastRowKey = $null
            }
        }
        $Metadata = @{ Count = $Rows.Count }
        if ($At -lt $Plan.Count) { $Metadata.nextLink = '{0}|{1}' -f $Plan[$At], $LastRowKey }
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = @($Rows); Metadata = $Metadata }
            })
    }

    if ($FilterConditions) {
        $Table.Filter = $FilterConditions -join ' and '
    }
    $AuditLogs = foreach ($Row in @(Get-CIPPAzDataTableEntity @Table)) {
        if ($Tenants.defaultDomainName -contains $Row.Tenant) { & $Shape $Row }
    }

    $Body = @{
        Results  = @($AuditLogs | Sort-Object -Property Timestamp -Descending)
        Metadata = @{
            Count  = $AuditLogs.Count
            Filter = $Table.Filter ?? ''
        }
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $Body
        })
}
