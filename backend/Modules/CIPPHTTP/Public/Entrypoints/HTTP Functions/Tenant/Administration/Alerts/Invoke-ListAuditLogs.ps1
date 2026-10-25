function Invoke-ListAuditLogs {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.Read
    .DESCRIPTION
        Lists audit log entries from the CIPP audit log store, filterable by tenant, date range, and log ID. Kind=Threshold
        lists only repeated activity alerts (one user or app doing something a set number of times within a window);
        AlertType says which kind each entry is, and TimesRepeated how many times for a repeated activity alert. A single
        repeated activity alert (LogId) also returns RelatedRecords: the records kept with it (time, operation, item,
        IP address, device), up to 500.
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
    if ($FilterConditions) {
        $Table.Filter = $FilterConditions -join ' and '
    }

    $Tenants = Get-Tenants -IncludeErrors

    $AuditLogs = Get-CIPPAzDataTableEntity @Table | Where-Object { $Tenants.defaultDomainName -contains $_.Tenant } | ForEach-Object {
        $_.Data = try { $_.Data | ConvertFrom-Json } catch { $_.AuditData }
        $Raw = $_.Data.RawData
        [pscustomobject]@{
            LogId          = $_.RowKey
            Timestamp      = $Raw.CreationTime
            Tenant         = $_.Tenant
            Title          = $_.Title
            AlertType      = if ($_.RowKey -like 'threshold-*') { 'Repeated activity' } else { 'Single event' }
            Workload       = $Raw.Workload
            Operation      = $Raw.Operation
            User           = $Raw.UserId
            TimesRepeated  = $Raw.CIPPThresholdCount
            Data           = $_.Data
        }
    }

    # One saved repeated activity alert also returns the records kept with it (AuditLogRelatedRecords).
    if ($LogID -and @($AuditLogs).Count -eq 1 -and $AuditLogs[0].AlertType -eq 'Repeated activity') {
        $RelatedTable = Get-CIPPTable -TableName 'AuditLogRelatedRecords'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value ([string]$AuditLogs[0].Tenant) -Type 'String'
        $Related = Get-CIPPAzDataTableEntity @RelatedTable -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$LogID'"
        if ($Related.Records) {
            $AuditLogs[0] | Add-Member -NotePropertyName RelatedRecords -NotePropertyValue @([CIPP.CippJson]::ConvertFromJson([string]$Related.Records)) -Force
        }
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
