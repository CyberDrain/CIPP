function Invoke-ListLicenseChanges {
    <#
    .FUNCTIONALITY
        Entrypoint,TenantGroup
    .ROLE
        Tenant.Directory.Read
    .SYNOPSIS
        List licences added to and removed from users in the last 30 days
    .DESCRIPTION
        Lists one row per licence added to or removed from a user in the last 30 days, with who made the change (a user or an app such as group-based licensing), read from the Entra directory audit log. The audit log needs Entra ID P1. Supports UseReportDB=true to serve cached data from the reporting database; AllTenants always uses the cache.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    # The tenant to list licence changes for, or AllTenants for every tenant (served from the cache)
    $TenantFilter = $Request.Query.tenantFilter
    # Serve from the reporting database cache instead of the live audit log. AllTenants always uses the cache.
    $UseReportDB = $Request.Query.UseReportDB -eq $true

    try {
        if ($TenantFilter -eq 'AllTenants') {
            $ByTenant = Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'LicenseChanges' -ByTenant
            $Body = @(foreach ($Tenant in $ByTenant.Keys) {
                    foreach ($Row in $ByTenant[$Tenant]) {
                        $Parsed = try { [CIPP.CippJson]::ConvertFromJson($Row.Data, $null) } catch { continue }
                        $Parsed.PSObject.Properties.Add([psnoteproperty]::new('Tenant', $Tenant))
                        $Parsed.PSObject.Properties.Add([psnoteproperty]::new('CacheTimestamp', $Row.Timestamp))
                        $Parsed
                    }
                })
        } elseif ($UseReportDB) {
            $Rows = @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'LicenseChanges')
            if ($Rows.Count -eq 0) {
                throw [System.Management.Automation.ItemNotFoundException]::new("No cached licence changes for $TenantFilter. Sync the report data first.")
            }
            $Body = @(foreach ($Row in $Rows) {
                    if ($Row.RowKey -eq 'LicenseChanges-Count') { continue }
                    $Parsed = try { [CIPP.CippJson]::ConvertFromJson($Row.Data, $null) } catch { continue }
                    $Parsed.PSObject.Properties.Add([psnoteproperty]::new('CacheTimestamp', $Row.Timestamp))
                    $Parsed
                })
        } else {
            $Start = [datetime]::UtcNow.AddDays(-30).ToString('s') + 'Z'
            $Uri = "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=activityDisplayName eq 'Change user license' and activityDateTime ge $Start&`$select=id,activityDateTime,activityDisplayName,result,initiatedBy,targetResources,additionalDetails&`$top=999"
            $Body = @(New-GraphGetRequest -uri $Uri -tenantid $TenantFilter -AsApp $true -Stream | ConvertFrom-CIPPLicenseAuditEvent -TenantFilter $TenantFilter)
        }
        $Body = @($Body | Sort-Object -Property activityDateTime -Descending)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to list licence changes: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $Body = @{ Error = $ErrorMessage.NormalizedError }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
