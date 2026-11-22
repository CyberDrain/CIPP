function Push-StoreStorageLargeFiles {
    <#
    .SYNOPSIS
        Post-execution function that writes the large file scan to the cache.

    .DESCRIPTION
        Flattens the file rows returned by every Push-DBCacheStorageLargeFilesBatch activity and writes
        StorageLargeFiles once. Each site gets one outcome: read if any batch read it, otherwise not read. A site that
        was not read, that no batch returned (ExpectedSiteUrls), or that had no usage figure (UnmeasuredSiteUrls)
        keeps its rows from the previous scan. Each file is written once. A run in which no site could be read writes
        nothing and fails, so the previous scan stays.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.Parameters.TenantFilter
    $TableName = 'CippStorageLargeFiles'

    try {
        $Read = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $NotRead = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($BatchResult in @($Item.Results)) {
            foreach ($Site in @($BatchResult.Sites)) {
                if (-not $Site) { continue }
                $SiteUrl = [string]$Site.SiteUrl
                if ($Site.Status -eq 'Full') {
                    if (-not $Read.ContainsKey($SiteUrl)) { $Read[$SiteUrl] = $Site.Rows }
                } else {
                    $null = $NotRead.Add($SiteUrl)
                }
            }
        }
        foreach ($SiteUrl in @($Item.Parameters.ExpectedSiteUrls)) {
            if ($SiteUrl) { $null = $NotRead.Add([string]$SiteUrl) }
        }
        $NotRead.ExceptWith($Read.Keys)

        if ($Read.Count -eq 0) {
            throw "no site could be read this run for $TenantFilter ($($NotRead.Count) not read); the previous scan was left in place"
        }

        $Keep = [System.Collections.Generic.HashSet[string]]::new($NotRead, [System.StringComparer]::OrdinalIgnoreCase)
        foreach ($SiteUrl in @($Item.Parameters.UnmeasuredSiteUrls)) {
            if ($SiteUrl -and -not $Read.ContainsKey([string]$SiteUrl)) { $null = $Keep.Add([string]$SiteUrl) }
        }

        $Rows = [System.Collections.Generic.List[object]]::new()
        $Written = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($SiteRows in $Read.Values) {
            foreach ($Row in @($SiteRows)) {
                if ($Row -and $Written.Add([string]$Row.id)) { $Rows.Add($Row) }
            }
        }

        $Restored = 0
        if ($Keep.Count -gt 0) {
            foreach ($Existing in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'StorageLargeFiles' -TableName $TableName)) {
                if ($Existing.rowType -eq 'File' -and $Keep.Contains([string]$Existing.siteUrl) -and $Written.Add([string]$Existing.id)) {
                    $Rows.Add($Existing)
                    $Restored++
                }
            }
        }

        Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'StorageLargeFiles' -TableName $TableName -Data @($Rows) -AddCount -ClearOnEmpty

        if ($NotRead.Count -gt 0) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached StorageLargeFiles for $TenantFilter : $($NotRead.Count) sites could not be read this run and keep their files from the previous scan ($Restored files kept). $($Read.Count) sites were read." -sev Warning
        } else {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Cached StorageLargeFiles for $TenantFilter : $($Rows.Count) files from $($Read.Count) sites" -sev Info
        }
    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to store StorageLargeFiles: $($_.Exception.Message)" -sev Error -LogData (Get-CippException -Exception $_)
        throw
    }
}
