function Invoke-ExecGetStorageReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Site.Read
    .DESCRIPTION
        Server-renders the SharePoint & OneDrive Storage report as application/pdf bytes: site and OneDrive
        usage, per-library version history estimates and version policies, recycle bins, inactive sites, and the
        largest files with what archiving them would save. Reads the CIPP reporting cache only (usage sync,
        cleanup scan and large file scan); nothing is read live.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName

    try {
        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'A tenantFilter is required' })
        }
        $BrandingPresetId = [string]($Request.Body.brandingPresetId ?? $Request.Query.brandingPresetId)
        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter -BrandingPresetId $BrandingPresetId

        # The usage readers throw when their cache has never synced; the report then shows that section as empty.
        $Sites = try { @(Get-CIPPSharePointSiteUsageReport -TenantFilter $TenantFilter -ErrorAction Stop) } catch { @() }
        $OneDrive = try { @(Get-CIPPOneDriveUsageReport -TenantFilter $TenantFilter -ErrorAction Stop) } catch { @() }
        $Scan = @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'StorageCleanupScan' -TableName 'CippStorageCleanupScan')
        # The archive section is optional: an unreadable large file scan or tenant configuration leaves it out.
        $LargeFiles = try {
            @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'StorageLargeFiles' -TableName 'CippStorageLargeFiles')
        } catch {
            Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Storage report: the large file scan could not be read, so the report leaves out the large files: $($_.Exception.Message)" -Sev 'Warning'
            @()
        }
        $Archive = $null
        try {
            foreach ($Row in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'SPOTenant')) {
                if ($Row) {
                    $Archive = $Row
                    break
                }
            }
        } catch {
            Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Storage report: the SharePoint tenant settings could not be read, so the report leaves out the Microsoft 365 Archive settings: $($_.Exception.Message)" -Sev 'Warning'
        }

        $Report = Build-CippStorageReportTree -Data @{
            TenantName = $TenantName
            sites      = $Sites
            oneDrive   = $OneDrive
            scan       = $Scan
            largeFiles = $LargeFiles
            archive    = $Archive
        }

        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Storage Report' -BrandingPresetId $BrandingPresetId
        $FileName = ("Storage_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render Storage report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
