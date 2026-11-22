function Invoke-ListSharePointArchiveSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Admin.Read
    .SYNOPSIS
        List a tenant's Microsoft 365 Archive settings and usage.
    .DESCRIPTION
        Returns whether Microsoft 365 Archive is turned on for the tenant, whether users may archive files, whether new
        sites allow it, how much storage is archived at file level, and the tenant storage quota. Read from the cached
        SharePoint tenant configuration, so it is as current as the last tenant data collection.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = $Request.Query.tenantFilter

    if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter is required.' } })
    }
    if ($TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Microsoft 365 Archive settings are shown one tenant at a time. Select a single tenant.' } })
    }

    try {
        $Row = $null
        foreach ($Item in @(Get-CIPPDbItem -TenantFilter $TenantFilter -Type 'SPOTenant')) {
            if ($Item.RowKey -notlike '*-Count') {
                $Row = $Item
                break
            }
        }
        if (-not $Row) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = 'No SharePoint configuration is stored for this tenant yet. It is collected with the nightly tenant data, or run the SPOTenant cache from the CIPP data cache settings.' } })
        }

        $Config = [CIPP.CippJson]::ConvertFromJson($Row.Data, $null)
        $Results = [PSCustomObject]@{
            archiveEnabled             = $Config.EnableSiteArchive -eq $true
            allowFileArchive           = $Config.AllowFileArchive -eq $true
            allowFileArchiveOnNewSites = $Config.AllowFileArchiveOnNewSitesByDefault -eq $true
            archivedFileStorageInBytes = [int64]($Config.ArchivedFileStorageUsageMB ?? 0) * 1MB
            storageQuotaInBytes        = [int64]($Config.StorageQuota ?? 0) * 1MB
            lastRefresh                = $Row.Timestamp
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Results = "Failed to read the Microsoft 365 Archive settings: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message $Results -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Results)
        })
}
