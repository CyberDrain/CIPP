function Get-CIPPSharePointLibraryContents {
    <#
    .SYNOPSIS
        Lists the folders and files in a SharePoint document library folder, or the largest files below it.
    .DESCRIPTION
        Reads one folder of a document library from Microsoft Graph and returns one row per folder and file with its
        size, last change and Microsoft 365 Archive status (active, archived, reactivating or unknown; $null for a
        folder). With -LargestFiles it returns the largest files anywhere below the folder instead: folders are opened
        largest first, and only while one could still hold a file larger than the smallest one kept, so the result is
        exact. If -MaxFolders folders have been opened and some could still hold a larger file, the largest of those
        are returned as Folder rows, so a caller can search inside them or tell the search did not finish.
    .PARAMETER SiteSegment
        The site as Microsoft Graph addresses it: its id, or 'host:/path:' for a site URL.
    .PARAMETER ListId
        The list id of the document library.
    .PARAMETER FolderId
        The drive item id of the folder to read. The top of the library when omitted.
    .PARAMETER MaxFiles
        How many files a -LargestFiles search keeps.
    .PARAMETER MaxFolders
        How many folders a -LargestFiles search opens at most.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [Parameter(Mandatory = $true)]
        [string]$SiteSegment,
        [Parameter(Mandatory = $true)]
        [string]$ListId,
        [string]$FolderId,
        [switch]$LargestFiles,
        [int]$MaxFiles = 50,
        [int]$MaxFolders = 60
    )

    $FoldersPerRequest = 20
    $UnopenedFoldersReturned = 20
    $Query = "`$select=id,name,size,folder,file,webUrl,lastModifiedDateTime,lastModifiedBy,parentReference&`$top=999"
    $StartPath = if ([string]::IsNullOrWhiteSpace($FolderId)) { 'root' } else { "items/$FolderId" }
    # file.archiveStatus is only returned by the beta endpoint.
    $Items = @(New-GraphGetRequest -uri "https://graph.microsoft.com/beta/sites/$SiteSegment/lists/$ListId/drive/$StartPath/children?$Query" -tenantid $TenantFilter -AsApp $true -ErrorAction Stop)

    if ($LargestFiles) {
        # Min-heap of the files kept, max-heap of the folders still worth opening: a folder no larger than the smallest
        # file kept cannot hold a larger one.
        $Kept = [System.Collections.Generic.PriorityQueue[object, long]]::new()
        $Pending = [System.Collections.Generic.PriorityQueue[object, long]]::new()
        $Smallest = [int64]-1
        $PrunedAt = [int64]-1
        $Opened = 0
        $Unopened = [System.Collections.Generic.List[object]]::new()
        # Each entry is one folder's reply; the library root is read as one.
        $Incoming = @(@{ body = @{ value = $Items } })
        $Items = $null

        while ($true) {
            foreach ($Reply in $Incoming) {
                foreach ($Item in $Reply.body.value) {
                    $ItemSize = [int64]$Item.size
                    if ($null -ne $Item.folder) {
                        if ([int]$Item.folder.childCount -gt 0 -and $ItemSize -gt $Smallest) { $Pending.Enqueue($Item, -$ItemSize) }
                    } elseif ($null -ne $Item.file) {
                        if ($Kept.Count -lt $MaxFiles) {
                            $Kept.Enqueue($Item, $ItemSize)
                        } else {
                            $null = $Kept.EnqueueDequeue($Item, $ItemSize)
                        }
                        if ($Kept.Count -ge $MaxFiles) {
                            $null = $Kept.TryPeek([ref]$null, [ref]$Smallest)
                        }
                    }
                }
            }
            $Incoming = $null

            # Only the largest folders still waiting can ever be opened or returned, and none no larger than the
            # smallest file kept, so the rest are dropped.
            $Usable = $MaxFolders - $Opened + $UnopenedFoldersReturned
            if ($Pending.Count -gt $Usable -or ($Smallest -gt $PrunedAt -and $Pending.Count -gt 0)) {
                $Waiting = [System.Collections.Generic.List[object]]::new()
                $Folder = $null
                $FolderSize = [int64]0
                while ($Waiting.Count -lt $Usable -and $Pending.TryDequeue([ref]$Folder, [ref]$FolderSize) -and -$FolderSize -gt $Smallest) {
                    $Waiting.Add($Folder)
                }
                $Pending.Clear()
                foreach ($Folder in $Waiting) { $Pending.Enqueue($Folder, -[int64]$Folder.size) }
                $PrunedAt = $Smallest
            }

            $Batch = [System.Collections.Generic.List[object]]::new()
            $FolderSize = [int64]0
            while ($Pending.TryPeek([ref]$null, [ref]$FolderSize) -and -$FolderSize -gt $Smallest -and $Batch.Count -lt $FoldersPerRequest -and $Opened -lt $MaxFolders) {
                $Batch.Add($Pending.Dequeue())
                $Opened++
            }
            if ($Batch.Count -eq 0) {
                # The folder limit was reached while some folders could still hold a larger file.
                while ($Unopened.Count -lt $UnopenedFoldersReturned -and $Pending.TryPeek([ref]$null, [ref]$FolderSize) -and -$FolderSize -gt $Smallest) {
                    $Unopened.Add($Pending.Dequeue())
                }
                break
            }

            $Requests = foreach ($Folder in $Batch) {
                @{
                    id     = [string]$Folder.id
                    method = 'GET'
                    url    = "drives/$($Folder.parentReference.driveId)/items/$($Folder.id)/children?$Query"
                }
            }
            $Answered = [System.Collections.Generic.HashSet[string]]::new()
            $Incoming = @(New-GraphBulkRequest -tenantid $TenantFilter -Requests @($Requests) -asapp $true -Version 'beta' -ErrorAction Stop)
            foreach ($Response in $Incoming) {
                if (($Response.status -as [int]) -ne 200) {
                    throw ($Response.body.error.message ?? "Reading a folder failed with status $($Response.status).")
                }
                # A continuation page that failed leaves the folder half read, so its largest file may be missing.
                if ($Response.PagingIncomplete -eq $true) {
                    throw "Reading a folder was incomplete: $($Response.PagingError)"
                }
                $null = $Answered.Add([string]$Response.id)
            }
            foreach ($Folder in $Batch) {
                if (-not $Answered.Contains([string]$Folder.id)) {
                    throw "Microsoft Graph did not return the contents of the folder $($Folder.name)."
                }
            }
        }

        $Largest = [System.Collections.Generic.List[object]]::new($Kept.Count)
        while ($Kept.Count -gt 0) { $Largest.Add($Kept.Dequeue()) }
        $Largest.Reverse()
        $Largest.AddRange($Unopened)
        $Items = $Largest
    }

    foreach ($Item in $Items) {
        $IsFolder = $null -ne $Item.folder
        $ParentPath = [string]$Item.parentReference.path
        $RootMarker = $ParentPath.IndexOf('root:')
        $FolderPath = if ($RootMarker -ge 0) { [uri]::UnescapeDataString($ParentPath.Substring($RootMarker + 5)) } else { '' }
        $ArchiveStatus = if ($IsFolder) {
            $null
        } else {
            switch ([string]$Item.file.archiveStatus) {
                '' { 'active' }
                'notArchived' { 'active' }
                'fullyArchived' { 'archived' }
                'reactivating' { 'reactivating' }
                default { 'unknown' }
            }
        }
        [PSCustomObject]@{
            id                   = $Item.id
            driveId              = $Item.parentReference.driveId
            name                 = $Item.name
            type                 = if ($IsFolder) { 'Folder' } else { 'File' }
            folderPath           = if ($FolderPath) { $FolderPath } else { '/' }
            sizeInBytes          = $Item.size
            itemCount            = $Item.folder.childCount
            archiveStatus        = $ArchiveStatus
            lastModifiedDateTime = $Item.lastModifiedDateTime
            lastModifiedBy       = $Item.lastModifiedBy.user.displayName
            webUrl               = $Item.webUrl
        }
    }
}
