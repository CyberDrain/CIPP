function Build-CippStorageReportTree {
    <#
    .SYNOPSIS
        Compose the SharePoint & OneDrive Storage report as a component tree.
    .DESCRIPTION
        Pure composition from already-gathered storage data. Returns @{ Blocks; Variables }: the
        component nodes for ConvertTo-CippReportPdf and the cover/footer report variables.
    .PARAMETER Data
        TenantName, sites[] (SharePoint usage rows), oneDrive[] (OneDrive usage rows), scan[]
        (StorageCleanupScan cache rows, rowType Site or Library; empty when no cleanup scan has run),
        largeFiles[] (StorageLargeFiles cache rows; empty when no large file scan has run) and archive
        (the cached SharePoint tenant configuration, or $null).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Data)

    $Sites = @($Data.sites ?? @())
    $OneDrive = @($Data.oneDrive ?? @())
    $Scan = @($Data.scan ?? @())
    $Libraries = @($Scan.Where({ $_.rowType -eq 'Library' }))
    $ScanSites = @($Scan.Where({ $_.rowType -eq 'Site' }))
    $LargeFiles = @(@($Data.largeFiles ?? @()).Where({ $_.rowType -eq 'File' }))
    $Archive = $Data.archive
    $Tenant = [System.Net.WebUtility]::HtmlEncode([string]$Data.TenantName)

    $Size = {
        param($Bytes)
        if ($null -eq $Bytes -or "$Bytes" -eq '') { return '-' }
        $B = [double]$Bytes
        if ($B -gt 0 -and $B -lt 1KB) { return '< 1 KB' }
        if ($B -ge 1TB) { '{0:N2} TB' -f ($B / 1TB) } elseif ($B -ge 1GB) { '{0:N2} GB' -f ($B / 1GB) } elseif ($B -ge 1MB) { '{0:N1} MB' -f ($B / 1MB) } else { '{0:N0} KB' -f ($B / 1KB) }
    }
    $Total = { param($Rows, $Field) [double](($Rows | Measure-Object -Property $Field -Sum).Sum) }
    $Pct = { param($Part, $Whole) $P = if ($Whole -gt 0) { [math]::Round($Part / $Whole * 100, 1) } else { 0 }; if ($P -eq 0 -and $Part -gt 0) { '< 0.1%' } else { "$P%" } }
    $Activity = { param($Row) $Date = $Row.lastActivityDate -as [datetime]; if ($Date) { $Date.ToString('yyyy-MM-dd') } else { 'None recorded' } }
    $SiteNames = @{}
    foreach ($S in $Sites) { if ($S.webUrl) { $SiteNames[([string]$S.webUrl).TrimEnd('/')] = $S.displayName } }
    $SiteName = { param($Url) $Key = ([string]$Url).TrimEnd('/'); if ($SiteNames[$Key]) { $SiteNames[$Key] } else { $Key } }

    # Same split as the Storage Report page: group and channel sites are Teams storage.
    $TeamsSites = @($Sites.Where({ (([string]$_.rootWebTemplate -split '#')[0] -replace '\s', '') -in 'group', 'teamchannel' }))
    $TeamsBytes = & $Total $TeamsSites 'storageUsedInBytes'
    $SpBytes = (& $Total $Sites 'storageUsedInBytes') - $TeamsBytes
    $OdBytes = & $Total $OneDrive 'storageUsedInBytes'
    $AllBytes = $SpBytes + $TeamsBytes + $OdBytes
    $LibBytes = & $Total $Libraries 'storageUsedInBytes'
    $VersionBytes = & $Total $Libraries 'versionEstimateBytes'
    $RecycleBytes = & $Total $ScanSites 'recycleTotalBytes'
    $VersionPct = & $Pct $VersionBytes $LibBytes
    $Scanned = $Libraries.Count -gt 0
    $Warn = '#744210'

    $Cutoff = (Get-Date).AddDays(-90)
    $Inactive = @($Sites.Where({ [double]($_.storageUsedInBytes ?? 0) -gt 0 -and (-not $_.lastActivityDate -or ($_.lastActivityDate -as [datetime]) -lt $Cutoff) }))
    # Count limit with no expiry: versions pile up to the limit on every file and are never trimmed by age.
    $Unbounded = @($Libraries.Where({ $_.versionTrimMode -eq 0 -and $_.versionPolicy -ne 'Versioning off' -and [double]($_.fileCount ?? 0) -gt 0 }))
    $LibRow = { param($L) @{ site = (& $SiteName $L.siteUrl); library = $L.libraryDisplayName; total = (& $Size $L.storageUsedInBytes); versions = (& $Size $L.versionEstimateBytes); share = (& $Pct ([double]($L.versionEstimateBytes ?? 0)) ([double]($L.storageUsedInBytes ?? 0))); policy = $L.versionPolicy } }
    $LibColumns = @(@{ header = 'Site'; key = 'site'; width = 1.8 }, @{ header = 'Library'; key = 'library'; width = 1.5 }, @{ header = 'Size'; key = 'total'; width = 0.9 }, @{ header = 'Versions'; key = 'versions'; width = 0.9 }, @{ header = 'Share'; key = 'share'; width = 0.7 }, @{ header = 'Version policy'; key = 'policy'; width = 1.8 })

    $Blocks = [System.Collections.Generic.List[object]]::new()

    # -- Executive Summary --
    $Blocks.Add((New-CippReportPage -Title 'Executive Summary' -Subtitle 'How much storage is in use, and where it goes'))
    $Blocks.Add((New-CippReportParagraph -Html ("<p>SharePoint and OneDrive storage grows with every file and every saved version of it. This report shows where storage in <b>$Tenant</b> is used today, how much of it is old file versions, and which sites and libraries are worth reviewing.</p>")))
    $Blocks.Add((New-CippReportStatRow -Stats @(
                @{ value = (& $Size $SpBytes); label = 'SharePoint' }
                @{ value = (& $Size $TeamsBytes); label = 'Teams' }
                @{ value = (& $Size $OdBytes); label = 'OneDrive' }
                if ($Scanned) { @{ value = (& $Size $VersionBytes); label = 'Version History (est.)' } }
                if ($ScanSites.Count -gt 0) { @{ value = (& $Size $RecycleBytes); label = 'Recycle Bins' } }
            )))
    if ($Scanned) {
        $Blocks.Add((New-CippReportInfoBox -Title 'Version history' -Content ("Old file versions take up an estimated {0} of the {1} held in the {2} document libraries reviewed ({3}). {4}" -f (& $Size $VersionBytes), (& $Size $LibBytes), $Libraries.Count, $VersionPct, $(if ($Unbounded.Count -eq 1) { '1 of those libraries keeps versions with no time limit.' } elseif ($Unbounded.Count -gt 1) { "$($Unbounded.Count) of those libraries keep versions with no time limit." } else { 'Every library with version history trims it automatically or by age.' }))))
    }

    # -- Where storage goes --
    $Blocks.Add((New-CippReportPage -Title 'Where Storage Goes' -Subtitle 'The largest sites and OneDrive accounts'))
    $Blocks.Add((New-CippReportTable -Title 'Largest SharePoint sites' -Limit 15 -EmptyText 'No SharePoint storage data is available.' -Columns @(@{ header = 'Site'; key = 'site'; width = 2.6 }, @{ header = 'Used'; key = 'used'; width = 1 }, @{ header = 'Of all storage'; key = 'share'; width = 1 }, @{ header = 'Last activity'; key = 'activity'; width = 1.1 }) -Rows @(
                $Sites | Sort-Object { [double]($_.storageUsedInBytes ?? 0) } -Descending | Select-Object -First 15 | ForEach-Object {
                    @{ site = $_.displayName; used = (& $Size $_.storageUsedInBytes); share = (& $Pct ([double]($_.storageUsedInBytes ?? 0)) $AllBytes); activity = (& $Activity $_) }
                })))
    $Blocks.Add((New-CippReportTable -Title 'Largest OneDrive accounts' -Limit 10 -EmptyText 'No OneDrive storage data is available.' -Columns @(@{ header = 'Owner'; key = 'owner'; width = 2.6 }, @{ header = 'Used'; key = 'used'; width = 1 }, @{ header = 'Last activity'; key = 'activity'; width = 1.1 }) -Rows @(
                $OneDrive | Sort-Object { [double]($_.storageUsedInBytes ?? 0) } -Descending | Select-Object -First 10 | ForEach-Object {
                    @{ owner = $(if ($_.ownerPrincipalName) { $_.ownerPrincipalName } else { $_.displayName }); used = (& $Size $_.storageUsedInBytes); activity = (& $Activity $_) }
                })))

    # -- Version history --
    if ($Scanned) {
        $Blocks.Add((New-CippReportPage -Title 'Version History' -Subtitle 'How much storage old file versions use, and the policy behind it'))
        $Blocks.Add((New-CippReportTable -Title 'Libraries with the most version history' -Limit 15 -EmptyText 'No library holds a measurable amount of version history.' -Columns $LibColumns -Rows @(
                    $Libraries.Where({ [double]($_.versionEstimateBytes ?? 0) -gt 0 }) | Sort-Object { [double]($_.versionEstimateBytes ?? 0) } -Descending | Select-Object -First 15 | ForEach-Object { & $LibRow $_ })))
        $Blocks.Add((New-CippReportHeading -Title 'Libraries Keeping Versions With No Time Limit'))
        $Blocks.Add((New-CippReportInfoBox -Title 'Why this matters' -Content 'A count limit with no expiry keeps up to that many versions of every file indefinitely. At the default of 500, a frequently edited file can hold hundreds of old copies. Automatic version trimming keeps recent versions and thins out old ones without losing recent history.'))
        if ($Unbounded.Count -gt 0) {
            $Blocks.Add((New-CippReportAlertBox -Title ("{0} with no time limit, holding an estimated {1}" -f $(if ($Unbounded.Count -eq 1) { '1 library' } else { "$($Unbounded.Count) libraries" }), (& $Size (& $Total $Unbounded 'versionEstimateBytes'))) -Colour $Warn -Content 'Consider automatic version trimming for these libraries, or a count limit combined with an age limit.'))
            $Blocks.Add((New-CippReportTable -Limit 15 -Columns $LibColumns -Rows @(
                        $Unbounded | Sort-Object { [double]($_.versionEstimateBytes ?? 0) } -Descending | Select-Object -First 15 | ForEach-Object { & $LibRow $_ })))
        } else {
            $Blocks.Add((New-CippReportClearBox -Title 'Version history is trimmed everywhere' -Content 'Every library holding version history trims it automatically or by age.'))
        }
    }

    # -- Cleanup opportunities --
    $Blocks.Add((New-CippReportPage -Title 'Other Cleanup Opportunities' -Subtitle 'Recycle bins and inactive sites'))
    $RecycleRows = @($ScanSites.Where({ [double]($_.recycleTotalBytes ?? 0) -gt 0 }) | Sort-Object { [double]$_.recycleTotalBytes } -Descending | Select-Object -First 10 | ForEach-Object {
            @{ site = $(if ($_.displayName) { $_.displayName } else { & $SiteName $_.siteUrl }); size = (& $Size $_.recycleTotalBytes); items = "$($_.recycleItemCount)" }
        })
    if ($ScanSites.Count -gt 0) {
        $Blocks.Add((New-CippReportParagraph -Text 'Deleted files stay in the site recycle bins for 93 days and count towards storage until they are removed.'))
        $Blocks.Add((New-CippReportTable -Title 'Largest recycle bins' -Limit 10 -EmptyText 'No recycle bin holds any data.' -Columns @(@{ header = 'Site'; key = 'site'; width = 2.6 }, @{ header = 'Size'; key = 'size'; width = 1 }, @{ header = 'Items'; key = 'items'; width = 0.8 }) -Rows $RecycleRows))
    }
    if ($Inactive.Count -gt 0) {
        $Blocks.Add((New-CippReportParagraph -Text ('{0} holding {1} had no activity in the last 90 days.' -f $(if ($Inactive.Count -eq 1) { '1 site' } else { "$($Inactive.Count) sites" }), (& $Size (& $Total $Inactive 'storageUsedInBytes')))))
    }
    $Blocks.Add((New-CippReportTable -Title 'Sites with no activity in 90 days' -Limit 10 -EmptyText 'Every site with stored data has been active in the last 90 days.' -Columns @(@{ header = 'Site'; key = 'site'; width = 2.6 }, @{ header = 'Used'; key = 'used'; width = 1 }, @{ header = 'Last activity'; key = 'activity'; width = 1.1 }) -Rows @(
                $Inactive | Sort-Object { [double]($_.storageUsedInBytes ?? 0) } -Descending | Select-Object -First 10 | ForEach-Object { @{ site = $_.displayName; used = (& $Size $_.storageUsedInBytes); activity = (& $Activity $_) } })))

    # -- Archive --
    $Dormant = @()
    if ($LargeFiles.Count -gt 0) {
        $ArchivedBytes = [double]($Archive.ArchivedFileStorageUsageMB ?? 0) * 1MB
        if ($ArchivedBytes -le 0) { $ArchivedBytes = & $Total $Sites 'archivedFileDiskUsedBytes' }
        $ArchiveCutoff = (Get-Date).AddMonths(-12)
        # Microsoft 365 Archive cannot archive OneNote files, SharePoint pages or anything in Site Assets.
        $Dormant = @($LargeFiles.Where({
                    $Changed = $_.lastModifiedDateTime -as [datetime]
                    $_.archiveStatus -eq 'active' -and $Changed -and $Changed -lt $ArchiveCutoff -and
                    [System.IO.Path]::GetExtension([string]$_.name) -notin '.one', '.onetoc2', '.aspx' -and
                    -not [string]::Equals([string]$_.libraryName, 'Site Assets', [System.StringComparison]::OrdinalIgnoreCase) -and -not ([string]$_.webUrl).StartsWith("$(([string]$_.siteUrl).TrimEnd('/'))/SiteAssets/", [System.StringComparison]::OrdinalIgnoreCase)
                }))
        $DormantBytes = & $Total $Dormant 'sizeInBytes'
        $FileRows = { param($Set) foreach ($F in @($Set | Sort-Object -Property sizeInBytes -Descending -Top 15)) { @{ file = $F.name; where = ("{0} / {1}{2}" -f $(if ($F.siteName) { $F.siteName } else { & $SiteName $F.siteUrl }), $F.libraryName, $(if ($F.folderPath -and $F.folderPath -ne '/') { $F.folderPath } else { '' })); size = (& $Size $F.sizeInBytes); changed = $(if ($F.lastModifiedDateTime -as [datetime]) { ($F.lastModifiedDateTime -as [datetime]).ToString('yyyy-MM-dd') } else { '-' }); status = $(switch ([string]$F.archiveStatus) { 'active' { 'Active' } 'archived' { 'Archived' } 'reactivating' { 'Reactivating' } default { 'Unknown' } }) } } }
        $FileColumns = @(@{ header = 'File'; key = 'file'; width = 2 }, @{ header = 'Where'; key = 'where'; width = 2.6 }, @{ header = 'Size'; key = 'size'; width = 0.9 }, @{ header = 'Last changed'; key = 'changed'; width = 1 }, @{ header = 'Status'; key = 'status'; width = 0.8 })

        $Blocks.Add((New-CippReportPage -Title 'Archive Opportunities' -Subtitle 'Large files that are rarely changed, and what archiving them would save'))
        $Blocks.Add((New-CippReportParagraph -Text 'Microsoft 365 Archive moves files that must be kept but are rarely opened into lower-cost storage. Archived files stay listed in their library and nothing is deleted, but they no longer count towards SharePoint storage. OneNote files, SharePoint pages and the contents of Site Assets libraries cannot be archived, so they are not counted as archive candidates.'))
        if (@($LargeFiles.Where({ $_.searchComplete -eq $false }, 'First')).Count -gt 0) {
            $Blocks.Add((New-CippReportInfoBox -Title 'Some folders were not read' -Content 'These are the largest files the scan found. In some sites it stopped before reading every folder, so a larger file may exist that is not listed here.'))
        }
        $Blocks.Add((New-CippReportStatRow -Stats @(
                    @{ value = (& $Size $ArchivedBytes); label = 'Total Currently Archived' }
                    @{ value = (& $Size (& $Total $LargeFiles 'sizeInBytes')); label = 'In The Largest Files' }
                    @{ value = (& $Size $DormantBytes); label = 'Not Changed In 12 Months' }
                )))
        $Blocks.Add((New-CippReportAlertBox -Title 'Archived files are not available straight away' -Colour $Warn -Content 'An archived file can be brought back at any time at no charge. For the first 7 days it comes back immediately. After that, reactivating it can take up to 24 hours, and the file cannot be opened until that finishes. A reactivated file cannot be archived again for 120 days. Only archive content the business does not need at short notice.'))
        if ($DormantBytes -gt 0) {
            $DormantGb = $DormantBytes / 1GB
            $Blocks.Add((New-CippReportInfoBox -Title 'What archiving would cost' -Content ('Archiving the {0} not changed in 12 months would free {1} of SharePoint storage. At Microsoft''s US list price, Archive storage is $0.05 per GB a month and is only charged for the amount by which active and archived storage together exceed the storage included with the tenant, so these files would cost at most ${2:N2} a month. Buying the same amount of extra SharePoint storage costs about ${3:N2} a month at Microsoft''s US list price of $0.20 per GB.' -f $(if ($Dormant.Count -eq 1) { '1 large file' } else { "$($Dormant.Count) large files" }), (& $Size $DormantBytes), ($DormantGb * 0.05), ($DormantGb * 0.2))))
        }
        if ($Archive -and $Archive.EnableSiteArchive -ne $true) {
            $Blocks.Add((New-CippReportInfoBox -Title 'Microsoft 365 Archive is not turned on yet' -Content 'Before anything can be archived, Microsoft 365 Archive has to be turned on for the tenant in the Microsoft 365 admin center, with pay-as-you-go billing set up.'))
        }
        $Blocks.Add((New-CippReportTable -Title 'Largest files' -Limit 15 -Columns $FileColumns -Rows @(
                    & $FileRows $LargeFiles)))
        if ($Dormant.Count -gt 0) {
            $Blocks.Add((New-CippReportTable -Title 'Large files not changed in 12 months' -Limit 15 -Columns $FileColumns -Rows @(
                        & $FileRows $Dormant)))
        } else {
            $Blocks.Add((New-CippReportParagraph -Text 'No eligible active files last changed more than 12 months ago were found among the largest files.'))
        }
    }

    # -- Recommendations --
    $Recommendations = @(
        @{ label = 'Turn on automatic version trimming.'; text = 'Set it as the tenant default and apply it to existing libraries. It keeps recent versions and removes old ones as they age, which stops version history growing without limit.' }
        @{ label = 'Clean up existing version history.'; text = 'A version cleanup job on the largest libraries frees space now. Changing the policy alone only affects versions created from then on.' }
        @{ label = 'Review inactive sites.'; text = 'Archive or delete sites nobody uses. Microsoft 365 Archive moves them to cheaper storage while keeping them recoverable.' }
        if ($Dormant.Count -gt 0) { @{ label = 'Archive large files nobody changes.'; text = 'Microsoft 365 Archive frees SharePoint storage without deleting anything. Allow up to 24 hours to get an archived file back, so keep anything needed at short notice out of it.' } }
        @{ label = 'Empty large recycle bins.'; text = 'Where deleted content is not needed, emptying the second-stage recycle bin frees the space straight away.' }
        @{ label = 'Re-run this report regularly.'; text = 'Storage grows steadily. Comparing reports over time shows whether the policies are working.' }
    )
    for ($i = 0; $i -lt $Recommendations.Count; $i++) { $Recommendations[$i]['marker'] = "$($i + 1)." }
    $Blocks.Add((New-CippReportPage -Title 'Recommendations' -Subtitle 'What to do about the findings'))
    $Blocks.Add((New-CippReportBullets -Items $Recommendations))

    @{
        Blocks    = @($Blocks)
        Variables = @{
            coverlabel         = 'Storage Review'
            coversubtitle      = "Where SharePoint and OneDrive storage is used at $($Data.TenantName), how much of it is old file versions, and what can be reclaimed."
            covermeta          = ("{0} SharePoint $([char]0x00B7) {1} Teams $([char]0x00B7) {2} OneDrive" -f (& $Size $SpBytes), (& $Size $TeamsBytes), (& $Size $OdBytes))
            covermetanote      = $(if ($Scanned) { "Version history: ~$(& $Size $VersionBytes) ($VersionPct of library storage)" } else { "$($OneDrive.Count) OneDrive accounts" })
            coverfooternote    = "Confidential $([char]0x2014) For Internal Use Only"
            coverfallbackimage = '/reportImages/laptop.jpg'
            footerlabel        = "$($Data.TenantName) $([char]0x2014) SharePoint & OneDrive Storage"
        }
    }
}
