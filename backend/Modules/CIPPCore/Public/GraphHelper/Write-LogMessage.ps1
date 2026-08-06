function Write-LogMessage {
    <#
    .FUNCTIONALITY
    Internal
    #>
    param(
        $message,
        $tenant = 'None',
        $API = 'None',
        $tenantId = $null,
        $headers,
        $user,
        $sev,
        $LogData = ''
    )
    if ($Headers.'x-ms-client-principal-idp' -eq 'azureStaticWebApps' -or !$Headers.'x-ms-client-principal-idp') {
        $user = $headers.'x-ms-client-principal'
        $username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails
    } elseif ($Headers.'x-ms-client-principal-idp' -eq 'aad') {
        $Table = Get-CIPPTable -TableName 'ApiClients'
        $Client = Get-CIPPAzDataTableEntity @Table -Filter "RowKey eq '$($headers.'x-ms-client-principal-name')'"
        $username = $Client.AppName ?? 'CIPP-API'
        $AppId = $headers.'x-ms-client-principal-name'
    } else {
        try {
            $username = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($user)) | ConvertFrom-Json).userDetails
        } catch {
            $username = $user
        }
    }

    if ($headers.'x-forwarded-for') {
        $ForwardedFor = $headers.'x-forwarded-for' -split ',' | Select-Object -First 1
        $IPRegex = '^(?<IP>(?:\d{1,3}(?:\.\d{1,3}){3}|\[[0-9a-fA-F:]+\]|[0-9a-fA-F:]+))(?::\d+)?$'
        $IPAddress = $ForwardedFor -replace $IPRegex, '$1' -replace '[\[\]]', ''
    }

    if ($LogData) { $LogData = ConvertTo-Json -InputObject $LogData -Depth 10 -Compress }

    $Table = Get-CIPPTable -tablename CippLogs

    if (!$tenant) { $tenant = 'None' }
    if (!$username) { $username = 'CIPP' }
    if ($sev -eq 'Debug' -and $env:DebugMode -ne $true) {
        return
    }
    $TzId = if ($env:CIPP_TIMEZONE) { $env:CIPP_TIMEZONE } else { 'UTC' }
    $LocalNow = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, $TzId)
    $PartitionKey = $LocalNow.ToString('yyyyMMdd')
    $TableRow = @{
        'Tenant'       = [string]$tenant
        'API'          = [string]$API
        'Message'      = [string]$message
        'Username'     = [string]$username
        'Severity'     = [string]$sev
        'sentAsAlert'  = $false
        'PartitionKey' = [string]$PartitionKey
        'RowKey'       = [string]([guid]::NewGuid()).ToString()
        'FunctionNode' = [string]$env:WEBSITE_SITE_NAME
        'LogData'      = [string]$LogData
    }
    if ($IPAddress) {
        $TableRow.IP = [string]$IPAddress
    }
    if ($AppId) {
        $TableRow.AppId = [string]$AppId
    }
    if ($tenantId) {
        $TableRow.Add('TenantID', [string]$tenantId)
    }
    $StandardInfo = $script:CippStandardInfoStorage.Value
    if ($StandardInfo) {
        $TableRow.Standard = [string]$StandardInfo.Standard
        $TableRow.StandardTemplateId = [string]$StandardInfo.StandardTemplateId
        if ($StandardInfo.IntuneTemplateId) {
            $TableRow.IntuneTemplateId = [string]$StandardInfo.IntuneTemplateId
        }
        if ($StandardInfo.ConditionalAccessTemplateId) {
            $TableRow.ConditionalAccessTemplateId = [string]$StandardInfo.ConditionalAccessTemplateId
        }
    }
    if ($script:CippScheduledTaskIdStorage.Value) {
        $TableRow.ScheduledTaskId = [string]$script:CippScheduledTaskIdStorage.Value

        # Track failures inside the running scheduled task so the scheduler can flag a task that finished
        # but had a step fail along the way. Capped to keep a pathological task from growing unbounded.
        if ($sev -in 'Error', 'Critical' -and $null -ne $script:CippScheduledTaskErrorStorage.Value -and $script:CippScheduledTaskErrorStorage.Value.Count -lt 25) {
            $script:CippScheduledTaskErrorStorage.Value.Add([string]$message)
        }
    }
    if ($script:CippBaselineRunIdStorage.Value) {
        $TableRow.BaselineRunId = [string]$script:CippBaselineRunIdStorage.Value
    }

    $Table.Entity = $TableRow
    Add-CIPPAzDataTableEntity @Table | Out-Null
}
