function Invoke-CIPPCloudBackupDriveRestoreStep {
    <#
    .SYNOPSIS
        Restores (or, without Context.Apply, previews) the next batch of a OneDrive or SharePoint restore job.
    .DESCRIPTION
        Returns { State; Done; Results; Bytes }. A batch is up to 20 entries, cut short once 256 MiB has been uploaded.
        A file already at the target with the same content is skipped in every conflict mode, so a repeated step does
        not restore it twice. A preview only reads the target.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context,
        $State
    )

    $BatchSize = 20
    $ByteBudget = 256MB
    $Tenant = $Context.TenantFilter
    $Apply = $Context.Apply -eq $true
    $SharePoint = $Context.Workload -eq 'sharepoint'
    $ConflictAction = if ($Context.ConflictAction -in @('Overwrite', 'Copy')) { [string]$Context.ConflictAction } else { 'Skip' }
    $Behavior = @{ Skip = 'fail'; Overwrite = 'replace'; Copy = 'rename' }[$ConflictAction]
    $Target = $Context.Target
    $SameOwner = $Context.SourceRemoved -ne $true -and [string]$Target.OwnerId -eq [string]$Context.SourceOwnerId
    $Offset = [int]$State.Offset
    $SourceName = [string]$State.SourceName

    $InvalidName = '[\\/:*?"<>|]'
    $RestoredFolder = ([string]$Context.RestoredFolderName -replace $InvalidName, '-').Trim(' ', '.')
    if (-not $RestoredFolder) { $RestoredFolder = 'Restored ' + [datetime]::UtcNow.ToString('yyyy-MM-dd HH-mm', [cultureinfo]::InvariantCulture) }
    $CopySuffix = " ($($RestoredFolder.Substring(0, 1).ToLowerInvariant())$($RestoredFolder.Substring(1)))"

    if (-not $SameOwner) {
        if (-not $Target.DriveId) {
            throw [System.ArgumentException]::new('The target user has no OneDrive to restore into.')
        }
        if (-not $SharePoint -and -not $SourceName) {
            try {
                $SourceUser = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($Context.SourceOwnerId)?`$select=userPrincipalName" -tenantid $Tenant -asapp $true
                $SourceName = [string]$SourceUser.userPrincipalName
            } catch {
                $SourceName = ''
            }
            if (-not $SourceName) { $SourceName = [string]$Context.SourceOwnerId }
            $SourceName = ($SourceName -replace $InvalidName, '-').Trim(' ', '.')
        }
    }

    $Entries = @(Get-CIPPCloudBackupJobItemBatch -Context $Context -Offset $Offset -Count $BatchSize)

    $Plans = [System.Collections.Generic.List[hashtable]]::new()
    $Requests = [System.Collections.Generic.List[hashtable]]::new()
    $LookupIds = @{}
    foreach ($Entry in $Entries) {
        $Type = [string]$Entry.Type
        $Name = [string]$Entry.Name
        $Plan = @{
            Entry   = $Entry
            Result  = [pscustomobject]@{ Key = $Entry.Key; Name = $Name; Path = $Entry.Path; Type = $Type; Action = 'NotRestorable'; Status = 'Skipped'; Message = $null; TargetPath = $null }
            DriveId = $null
        }
        $Plans.Add($Plan)

        if ($Entry.Deleted -eq $true) {
            $Plan.Result.Message = 'The item was deleted at this point in time.'
            continue
        }
        if ($Type -notin @('file', 'folder') -or -not $Name -or -not $Entry.Key) {
            $Plan.Result.Message = 'This item cannot be restored to a drive.'
            continue
        }

        $Extra = $Entry.Extra
        $Plan.DriveId = if (-not $SameOwner) { [string]$Target.DriveId } elseif (-not $SharePoint -and $Target.DriveId) { [string]$Target.DriveId } else { [string]$Extra.driveId }
        if (-not $Plan.DriveId) {
            $Plan.Result.Message = 'The backup does not say which drive this item came from.'
            continue
        }

        $Segments = [System.Collections.Generic.List[string]]::new()
        if (-not $SameOwner) {
            $Segments.Add($RestoredFolder)
            $Segments.Add($(if ($SharePoint) { (([string]($Extra.driveName ?? 'Library')) -replace $InvalidName, '-').Trim(' ', '.') } else { $SourceName }))
        } elseif ($Context.Location -ne 'Original') {
            $Segments.Add($RestoredFolder)
        }
        foreach ($Segment in ([string]$Entry.Path).Split('/')) {
            if ($Segment) { $Segments.Add($Segment) }
        }
        if ($Type -eq 'folder') { $Segments.Add($Name) }
        $Plan.Segments = $Segments
        $Plan.FolderPath = if ($Segments.Count -gt 0) { '/' + ($Segments -join '/') } else { '' }
        $Plan.EscapedFolder = if ($Segments.Count -gt 0) { ':/' + (@(foreach ($Segment in $Segments) { [uri]::EscapeDataString($Segment) }) -join '/') } else { '' }

        if ($Type -eq 'folder') {
            $Plan.Result.TargetPath = $Plan.FolderPath
            $Plan.LookupId = "$($Plans.Count)"
            $Requests.Add(@{ id = $Plan.LookupId; method = 'GET'; url = "drives/$($Plan.DriveId)/root$($Plan.EscapedFolder)?`$select=id,name,file,folder" })
            continue
        }

        $Plan.Result.TargetPath = "$($Plan.FolderPath)/$Name"
        $Plan.LookupId = "$($Plans.Count)"
        $Requests.Add(@{ id = $Plan.LookupId; method = 'GET'; url = "drives/$($Plan.DriveId)/root$(if ($Plan.EscapedFolder) { $Plan.EscapedFolder } else { ':' })/$([uri]::EscapeDataString($Name))?`$select=id,name,file,folder" })
        if ($ConflictAction -eq 'Copy') {
            $Extension = [System.IO.Path]::GetExtension($Name)
            $BaseName = $Name.Substring(0, $Name.Length - $Extension.Length)
            $Plan.CopyName = if ($BaseName) { "$BaseName$CopySuffix$Extension" } else { "$Name$CopySuffix" }
            $Plan.CopyLookupId = "$($Plans.Count)c"
            $Requests.Add(@{ id = $Plan.CopyLookupId; method = 'GET'; url = "drives/$($Plan.DriveId)/root$(if ($Plan.EscapedFolder) { $Plan.EscapedFolder } else { ':' })/$([uri]::EscapeDataString($Plan.CopyName))?`$select=id,name,file,folder" })
        }
        if ($Plan.EscapedFolder -and -not $LookupIds.ContainsKey("$($Plan.DriveId)|$($Plan.FolderPath.ToLowerInvariant())")) {
            $FolderLookupId = "f$($Plans.Count)"
            $LookupIds["$($Plan.DriveId)|$($Plan.FolderPath.ToLowerInvariant())"] = $FolderLookupId
            $Requests.Add(@{ id = $FolderLookupId; method = 'GET'; url = "drives/$($Plan.DriveId)/root$($Plan.EscapedFolder)?`$select=id,folder" })
        }
    }

    $Lookups = @{}
    if ($Requests.Count -gt 0) {
        foreach ($Response in @(New-GraphBulkRequest -tenantid $Tenant -asapp $true -Version 'v1.0' -Requests @($Requests))) {
            $Lookups[[string]$Response.id] = $Response
        }
    }

    $FolderIds = @{}
    foreach ($Entry in $LookupIds.GetEnumerator()) {
        $Found = $Lookups[$Entry.Value]
        if ($Found.status -eq 200 -and $Found.body.folder) { $FolderIds[$Entry.Key] = [string]$Found.body.id }
    }

    foreach ($Plan in $Plans) {
        if (-not $Plan.LookupId) { continue }
        $Result = $Plan.Result
        $Found = $Lookups[$Plan.LookupId]
        $Status = [int]$Found.status
        if ($Status -ne 200 -and $Status -ne 404) {
            $Result.Status = 'Failed'
            $Result.Message = "The target could not be checked: $($Found.body.error.message ?? "status $Status")"
            $Plan.LookupId = $null
            continue
        }
        $Existing = if ($Status -eq 200) { $Found.body } else { $null }

        if ($Plan.Entry.Type -eq 'folder') {
            if (-not $Existing) {
                $Result.Action = 'Create'
                $Result.Status = 'Planned'
            } elseif ($Existing.folder) {
                $Result.Action = 'Skip'
                $Result.Message = 'The folder already exists.'
                $FolderIds["$($Plan.DriveId)|$($Plan.FolderPath.ToLowerInvariant())"] = [string]$Existing.id
            } else {
                $Result.Message = 'A file with the same name is in the way of this folder.'
            }
            continue
        }

        $Hash = [string]$Plan.Entry.Extra.hash
        $Identical = $Existing.file -and $Hash -and $Hash -in @($Existing.file.hashes.quickXorHash, $Existing.file.hashes.sha256Hash, $Existing.file.hashes.sha1Hash)
        if (-not $Existing) {
            $Result.Action = 'Create'
            $Result.Status = 'Planned'
            $Plan.TargetName = [string]$Plan.Entry.Name
        } elseif ($Identical) {
            $Result.Action = 'Skip'
            $Result.Message = 'The file is already there with the same content.'
        } elseif ($ConflictAction -eq 'Skip') {
            $Result.Action = 'Skip'
            $Result.Message = 'An item with this name already exists.'
        } elseif ($ConflictAction -eq 'Overwrite' -and $Existing.folder) {
            $Result.Message = 'A folder with the same name is in the way of this file.'
        } elseif ($ConflictAction -eq 'Overwrite') {
            $Result.Action = 'Overwrite'
            $Result.Status = 'Planned'
            $Plan.TargetName = [string]$Plan.Entry.Name
        } else {
            $Copy = $Lookups[$Plan.CopyLookupId]
            $CopyIdentical = $Copy.status -eq 200 -and $Copy.body.file -and $Hash -and $Hash -in @($Copy.body.file.hashes.quickXorHash, $Copy.body.file.hashes.sha256Hash, $Copy.body.file.hashes.sha1Hash)
            $Result.Action = 'Copy'
            $Result.TargetPath = "$($Plan.FolderPath)/$($Plan.CopyName)"
            if ($CopyIdentical) {
                $Result.Message = 'A restored copy with the same content is already there.'
            } else {
                $Result.Status = 'Planned'
                $Plan.TargetName = $Plan.CopyName
            }
        }
    }

    $Results = [System.Collections.Generic.List[object]]::new()
    $Bytes = [int64]0
    $Processed = 0
    $Client = $null
    $OnStop = $null
    try {
        foreach ($Plan in $Plans) {
            $Result = $Plan.Result
            $Processed++
            $Results.Add($Result)
            if (-not $Apply -or $Result.Status -ne 'Planned') { continue }

            try {
                $ParentId = if ($Plan.FolderPath) { $FolderIds["$($Plan.DriveId)|$($Plan.FolderPath.ToLowerInvariant())"] } else { 'root' }
                $Walk = if ($ParentId) { @() } else { $Plan.Segments }
                if (-not $ParentId) { $ParentId = 'root' }
                $FolderPath = ''
                foreach ($Segment in $Walk) {
                    $FolderPath = "$FolderPath/$Segment"
                    $CacheKey = "$($Plan.DriveId)|$($FolderPath.ToLowerInvariant())"
                    if ($FolderIds[$CacheKey]) {
                        $ParentId = $FolderIds[$CacheKey]
                        continue
                    }
                    try {
                        $Created = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/drives/$($Plan.DriveId)/items/$ParentId/children" -tenantid $Tenant -AsApp $true -body (ConvertTo-Json -InputObject @{ name = $Segment; folder = @{}; '@microsoft.graph.conflictBehavior' = 'fail' } -Compress)
                        $ParentId = [string]$Created.id
                    } catch {
                        if ("$($_.Exception.Message) $($_.Exception.Data['RawErrorBody'])" -notmatch 'nameAlreadyExists|already exists') { throw }
                        $Escaped = @(foreach ($Part in $FolderPath.Split('/')) { if ($Part) { [uri]::EscapeDataString($Part) } }) -join '/'
                        $Existing = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/drives/$($Plan.DriveId)/root:/$($Escaped)?`$select=id,folder" -tenantid $Tenant -asapp $true
                        if (-not $Existing.folder) { throw "A file named '$Segment' is in the way of folder $FolderPath." }
                        $ParentId = [string]$Existing.id
                    }
                    $FolderIds[$CacheKey] = $ParentId
                }

                if ($Plan.Entry.Type -eq 'file') {
                    if (-not $Client) {
                        $Client = [System.Net.Http.HttpClient]::new()
                        $Client.Timeout = [System.TimeSpan]::FromMinutes(10)
                        $StopToken = $PSCmdlet.PipelineStopToken
                        # Disposing the client aborts a stalled upload when the worker stops the pipeline.
                        $OnStop = if ($StopToken) { $StopToken.Register([Action]$Client.Dispose) }
                    }
                    $Uploaded = Restore-CIPPCloudBackupDriveFile -Context $Context -Entry $Plan.Entry -DriveId $Plan.DriveId -ParentId $ParentId -Name $Plan.TargetName -ConflictBehavior $Behavior -Client $Client
                    $Bytes += [int64]$Uploaded.Bytes
                    $Result.TargetPath = "$($Plan.FolderPath)/$($Uploaded.Name)"
                }
                $Result.Status = 'Succeeded'
            } catch {
                if ($_.Exception.Data['Conflict'] -and $ConflictAction -eq 'Skip') {
                    $Result.Action = 'Skip'
                    $Result.Status = 'Skipped'
                    $Result.Message = 'An item with this name already exists.'
                } else {
                    $Result.Status = 'Failed'
                    $Result.Message = $_.Exception.Message
                }
            }
            if ($Bytes -ge $ByteBudget) { break }
        }
    } finally {
        if ($OnStop) { $OnStop.Dispose() }
        if ($Client) { $Client.Dispose() }
    }

    [pscustomobject]@{
        State   = @{ Offset = $Offset + $Processed; SourceName = $SourceName }
        Done    = $Entries.Count -lt $BatchSize -and $Processed -eq $Entries.Count
        Results = @($Results)
        Bytes   = $Bytes
    }
}
