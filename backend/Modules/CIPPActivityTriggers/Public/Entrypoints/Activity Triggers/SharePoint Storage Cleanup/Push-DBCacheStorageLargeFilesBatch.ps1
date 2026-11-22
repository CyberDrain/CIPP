function Push-DBCacheStorageLargeFilesBatch {
    <#
    .SYNOPSIS
        Finds the largest files in a batch of SharePoint sites.

    .DESCRIPTION
        For each site, searches every document library for its largest files (Get-CIPPSharePointLibraryContents
        -LargestFiles) and keeps up to 25 of the largest across the site. Each library search opens at most 500 folders; when
        a search stops there with folders left that could hold a larger file, the site's rows carry
        searchComplete = $false. A search that stopped there without keeping any file returns the site as Skipped, so
        its earlier rows are kept. Each site is wrapped in its own try/catch, so one unreadable site is returned as
        Skipped and the rest of the batch still completes.

    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $TenantFilter = $Item.TenantFilter
    $FilesPerSite = 25
    $MaxFoldersPerLibrary = 500
    $SiteResults = [System.Collections.Generic.List[object]]::new()

    foreach ($Site in @($Item.Sites)) {
        $SiteUrl = ([string]$Site.webUrl).TrimEnd('/')
        try {
            $ParsedUrl = [System.Uri]$SiteUrl
            $SiteSegment = if ($ParsedUrl.AbsolutePath -in @('', '/')) { $ParsedUrl.Host } else { "$($ParsedUrl.Host):$($ParsedUrl.AbsolutePath):" }
            $CollectedAt = (Get-Date).ToUniversalTime().ToString('o')

            $Files = [System.Collections.Generic.List[object]]::new()
            $SearchComplete = $true
            foreach ($List in @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteSegment/lists?`$select=id,displayName,list" -tenantid $TenantFilter -AsApp $true -ErrorAction Stop)) {
                if ($List.list.hidden -eq $true -or $List.list.template -ne 'documentLibrary') { continue }
                foreach ($File in @(Get-CIPPSharePointLibraryContents -TenantFilter $TenantFilter -SiteSegment $SiteSegment -ListId $List.id -LargestFiles -MaxFiles $FilesPerSite -MaxFolders $MaxFoldersPerLibrary)) {
                    # A folder row is one the search stopped before opening.
                    if ($File.type -ne 'File') {
                        $SearchComplete = $false
                        continue
                    }
                    $Files.Add([PSCustomObject]@{
                            rowType              = 'File'
                            id                   = "$($File.driveId)_$($File.id)"
                            itemId               = $File.id
                            driveId              = $File.driveId
                            siteUrl              = $SiteUrl
                            siteName             = $Site.displayName
                            libraryId            = $List.id
                            libraryName          = $List.displayName
                            name                 = $File.name
                            folderPath           = $File.folderPath
                            sizeInBytes          = $File.sizeInBytes
                            archiveStatus        = $File.archiveStatus
                            lastModifiedDateTime = $File.lastModifiedDateTime
                            lastModifiedBy       = $File.lastModifiedBy
                            webUrl               = $File.webUrl
                            collectedAt          = $CollectedAt
                            searchComplete       = $true
                        })
                }
            }

            $Rows = @($Files | Sort-Object -Property sizeInBytes -Descending -Top $FilesPerSite)
            if (-not $SearchComplete) {
                foreach ($Row in $Rows) { $Row.searchComplete = $false }
            }
            # A search that stopped early without keeping a file has nothing to show for the site, so its earlier rows stay.
            $Status = if (-not $SearchComplete -and $Rows.Count -eq 0) { 'Skipped' } else { 'Full' }
            if ($Status -eq 'Skipped') {
                Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "StorageLargeFiles: the search of '$SiteUrl' stopped before it found a file" -sev Warning
            }
            $SiteResults.Add([PSCustomObject]@{
                    SiteUrl = $SiteUrl
                    Status  = $Status
                    Rows    = $Rows
                })
        } catch {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "StorageLargeFiles: could not read '$SiteUrl': $($_.Exception.Message)" -sev Warning
            $SiteResults.Add([PSCustomObject]@{
                    SiteUrl = $SiteUrl
                    Status  = 'Skipped'
                    Rows    = @()
                })
        }
    }

    return [PSCustomObject]@{
        BatchNumber = $Item.BatchNumber
        Sites       = @($SiteResults)
    }
}
