function Invoke-CIPPCloudBackupExchangeStep {
    <#
    .SYNOPSIS
        Runs one bounded step of a mailbox backup: one folder delta page, one batch of removals for a deleted folder,
        the retry list, or one item delta page of one folder.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context,

        $State
    )

    $MaxRetry = 200
    $MaxAttempts = 3
    $RemovalsPerStep = 500
    $Graph = 'https://graph.microsoft.com/beta'
    $Tenant = $Context.TenantFilter
    $OwnerPrefix = ([string]$Context.OwnerPrefix).TrimEnd('/') + '/'

    $Warnings = [System.Collections.Generic.List[string]]::new()
    $IndexEntries = [System.Collections.Generic.List[object]]::new()
    $Items = 0
    $Bytes = [long]0
    $Deleted = 0
    $Done = $false

    $Folders = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($F in @($State.Folders)) {
        if ($null -ne $F) { $Folders.Add(@{ Id = [string]$F.Id; Name = [string]$F.Name; ParentId = [string]$F.ParentId; Type = [string]$F.Type; Hidden = [bool]$F.Hidden; Link = [string]$F.Link }) }
    }
    $Removals = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($R in @($State.Removals)) {
        if ($null -ne $R) { $Removals.Add(@{ Id = [string]$R.Id; Path = [string]$R.Path; Type = [string]$R.Type }) }
    }
    $Retry = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($R in @($State.Retry)) {
        if ($null -eq $R) { continue }
        $Created = if ($R.Created -is [datetime]) { $R.Created.ToUniversalTime().ToString('o') } else { [string]$R.Created }
        $Modified = if ($R.Modified -is [datetime]) { $R.Modified.ToUniversalTime().ToString('o') } else { [string]$R.Modified }
        $Retry.Add(@{ FolderId = [string]$R.FolderId; Id = [string]$R.Id; Class = [string]$R.Class; Size = [long]$R.Size; Created = $Created; Modified = $Modified; Attempts = [int]$R.Attempts; Deleted = [bool]$R.Deleted })
    }
    $S = @{
        MailboxId   = [string]$State.MailboxId
        Phase       = if ($State.Phase) { [string]$State.Phase } else { 'Folders' }
        FolderLink  = [string]$State.FolderLink
        FolderIndex = [int]$State.FolderIndex
    }
    $ById = [System.Collections.Generic.Dictionary[string, hashtable]]::new([System.StringComparer]::Ordinal)
    foreach ($F in $Folders) { $ById[$F.Id] = $F }

    if (-not $S.MailboxId) {
        $Settings = New-GraphGetRequest -uri "$Graph/users/$($Context.OwnerId)/settings/exchange" -tenantid $Tenant -AsApp $true -noPagination $true
        if (-not $Settings.primaryMailboxId) { throw "No mailbox found for $($Context.OwnerId)." }
        $S.MailboxId = [string]$Settings.primaryMailboxId
    }
    $Mailbox = $S.MailboxId

    $FolderPage = $null
    $FolderChanges = [System.Collections.Generic.List[hashtable]]::new()
    if ($S.Phase -eq 'Folders') {
        $Uri = if ($S.FolderLink) { $S.FolderLink } else { "$Graph/admin/exchange/mailboxes/$Mailbox/folders/delta?`$select=id,displayName,parentFolderId,type,isHidden" }
        $FolderPage = New-GraphGetRequest -uri $Uri -tenantid $Tenant -AsApp $true -noPagination $true -SkipValueExtraction -extraHeaders @{ Prefer = 'odata.maxpagesize=200' }
        foreach ($F in $FolderPage.value) {
            $Id = [string]$F.id
            if ($null -ne $F.'@removed') {
                if ($ById.ContainsKey($Id)) { $FolderChanges.Add(@{ Folder = $ById[$Id]; Removed = $true }) }
                continue
            }
            if ($ById.ContainsKey($Id)) {
                $Known = $ById[$Id]
                $Known.Name = [string]$F.displayName
                $Known.ParentId = [string]$F.parentFolderId
                $Known.Type = [string]$F.type
                $Known.Hidden = [bool]$F.isHidden
            } else {
                $Known = @{ Id = $Id; Name = [string]$F.displayName; ParentId = [string]$F.parentFolderId; Type = [string]$F.type; Hidden = [bool]$F.isHidden; Link = '' }
                $Folders.Add($Known)
                $ById[$Id] = $Known
            }
            $FolderChanges.Add(@{ Folder = $Known; Removed = $false })
        }
    }

    $Paths = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    foreach ($F in $Folders) {
        $Names = [System.Collections.Generic.List[string]]::new()
        $Cursor = $F.Id
        for ($Depth = 0; $Depth -lt 64 -and $ById.ContainsKey($Cursor); $Depth++) {
            $Names.Insert(0, $ById[$Cursor].Name)
            $Cursor = $ById[$Cursor].ParentId
        }
        $Paths[$F.Id] = $Names -join '/'
    }

    $ToRemove = [System.Collections.Generic.List[hashtable]]::new()

    if ($S.Phase -eq 'Folders') {
        foreach ($Change in $FolderChanges) {
            $F = $Change.Folder
            $Key = 'items/{0}/' -f $F.Id.Replace('/', '-').Replace('+', '_')
            $ParentPath = if ($Paths.ContainsKey($F.ParentId)) { $Paths[$F.ParentId] } else { '' }
            $IndexEntries.Add([pscustomobject]@{ k = $Key; p = $ParentPath; n = $F.Name; t = 'folder'; s = $null; m = $null; v = $null; d = $Change.Removed; x = [ordered]@{ id = $F.Id; parentId = $F.ParentId; type = $F.Type } })
            if ($Change.Removed) {
                $Removals.Add(@{ Id = $F.Id; Path = $Paths[$F.Id]; Type = $F.Type })
                [void]$Folders.Remove($F)
                [void]$ById.Remove($F.Id)
            }
        }
        if ($FolderPage.'@odata.nextLink') {
            $S.FolderLink = [string]$FolderPage.'@odata.nextLink'
        } else {
            $S.FolderLink = [string]$FolderPage.'@odata.deltaLink'
            $S.Phase = 'Removals'
            $S.FolderIndex = 0
        }
    } else {
        if ($S.Phase -eq 'Removals' -and $Removals.Count -eq 0) { $S.Phase = 'Retry' }
        if ($S.Phase -eq 'Retry' -and $Retry.Count -eq 0) { $S.Phase = 'Items' }

        if ($S.Phase -eq 'Removals') {
            $Removal = $Removals[0]
            $Type = if ($Removal.Type -like 'IPF.Appointment*') { 'event' } elseif ($Removal.Type -like 'IPF.Contact*') { 'contact' } else { 'message' }
            $FolderPrefix = 'items/{0}/' -f $Removal.Id.Replace('/', '-').Replace('+', '_')
            $Stored = @(Get-CIPPCloudBackupObjectList -Destination $Context.Destination -Prefix ($OwnerPrefix + $FolderPrefix))
            $Count = 0
            $Removed = 0
            foreach ($Object in $Stored) {
                if ($Count -ge $RemovalsPerStep) { break }
                $Count++
                $Key = ([string]$Object.Key).Substring($OwnerPrefix.Length)
                try {
                    $null = Remove-CIPPCloudBackupItem -Context $Context -ItemKey $Key
                } catch {
                    $Warnings.Add("Removing $Key failed: $($_.Exception.Message)")
                    continue
                }
                $Removed++
                if ($Key.EndsWith('.fts')) {
                    $Deleted++
                    $IndexEntries.Add([pscustomobject]@{ k = $Key; p = $Removal.Path; n = $null; t = $Type; s = $null; m = $null; v = $null; d = $true; x = $null })
                }
            }
            if ($Stored.Count -le $RemovalsPerStep -or $Removed -eq 0) { $Removals.RemoveAt(0) }
        } elseif ($S.Phase -eq 'Retry') {
            $Pending = $Retry.ToArray()
            $Retry.Clear()
            $ByFolder = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[hashtable]]]::new([System.StringComparer]::Ordinal)
            foreach ($R in $Pending) {
                if (-not $ById.ContainsKey($R.FolderId)) { continue }
                if ($R.Deleted) { $ToRemove.Add($R); continue }
                if (-not $ByFolder.ContainsKey($R.FolderId)) { $ByFolder[$R.FolderId] = [System.Collections.Generic.List[hashtable]]::new() }
                $ByFolder[$R.FolderId].Add($R)
            }
            foreach ($FolderId in $ByFolder.Keys) {
                $Result = Save-CIPPCloudBackupExchangeItem -Context $Context -MailboxId $Mailbox -FolderKey $FolderId.Replace('/', '-').Replace('+', '_') -FolderPath $Paths[$FolderId] -Items $ByFolder[$FolderId].ToArray()
                $Items += $Result.Items
                $Bytes += $Result.Bytes
                foreach ($W in $Result.Warnings) { $Warnings.Add($W) }
                foreach ($E in $Result.IndexEntries) { $IndexEntries.Add($E) }
                foreach ($R in $Result.Failed) {
                    if ($R.Attempts + 1 -lt $MaxAttempts) { $R.Attempts++; $Retry.Add($R) }
                    else { $Warnings.Add("Giving up on item $($R.Id) in $($Paths[$FolderId]) after $MaxAttempts attempts.") }
                }
            }
            $S.Phase = 'Items'
        } else {
            $Folder = $null
            while ($S.FolderIndex -lt $Folders.Count) {
                $Candidate = $Folders[$S.FolderIndex]
                if (-not $Candidate.Hidden -and ($Candidate.Type -like 'IPF.Note*' -or $Candidate.Type -like 'IPF.Appointment*' -or $Candidate.Type -like 'IPF.Contact*')) { $Folder = $Candidate; break }
                $S.FolderIndex++
            }
            if (-not $Folder) {
                $S.Phase = 'Folders'
                $S.FolderIndex = 0
                $Done = $true
            } else {
                $Path = $Paths[$Folder.Id]
                $Uri = if ($Folder.Link) { $Folder.Link } else { "$Graph/admin/exchange/mailboxes/$Mailbox/folders/$([uri]::EscapeDataString($Folder.Id))/items/delta?`$select=id,type,size,createdDateTime,lastModifiedDateTime,changeKey" }
                $Page = New-GraphGetRequest -uri $Uri -tenantid $Tenant -AsApp $true -noPagination $true -SkipValueExtraction -extraHeaders @{ Prefer = 'odata.maxpagesize=100' }
                $Changed = [System.Collections.Generic.List[hashtable]]::new()
                $NewRetry = [System.Collections.Generic.List[hashtable]]::new()
                foreach ($Item in $Page.value) {
                    if ($null -ne $Item.'@removed') {
                        $ToRemove.Add(@{ FolderId = $Folder.Id; Id = [string]$Item.id; Class = ''; Size = 0; Created = ''; Modified = ''; Attempts = 0; Deleted = $true })
                        continue
                    }
                    $Created = $Item.createdDateTime
                    $Modified = $Item.lastModifiedDateTime
                    $Changed.Add(@{
                            FolderId = $Folder.Id
                            Id       = [string]$Item.id
                            Class    = [string]$Item.type
                            Size     = [long]$Item.size
                            Created  = if ($Created -is [datetime]) { $Created.ToUniversalTime().ToString('o') } else { [string]$Created }
                            Modified = if ($Modified -is [datetime]) { $Modified.ToUniversalTime().ToString('o') } else { [string]$Modified }
                            Attempts = 0
                            Deleted  = $false
                        })
                }
                if ($Changed.Count -gt 0) {
                    $Result = Save-CIPPCloudBackupExchangeItem -Context $Context -MailboxId $Mailbox -FolderKey $Folder.Id.Replace('/', '-').Replace('+', '_') -FolderPath $Path -Items $Changed.ToArray()
                    $Items += $Result.Items
                    $Bytes += $Result.Bytes
                    foreach ($W in $Result.Warnings) { $Warnings.Add($W) }
                    foreach ($E in $Result.IndexEntries) { $IndexEntries.Add($E) }
                    foreach ($R in $Result.Failed) { $R.Attempts = 1; $NewRetry.Add($R) }
                }
                if ($Retry.Count + $NewRetry.Count + $ToRemove.Count -le $MaxRetry) {
                    foreach ($R in $NewRetry) { $Retry.Add($R) }
                    if ($Page.'@odata.nextLink') {
                        $Folder.Link = [string]$Page.'@odata.nextLink'
                    } else {
                        $Folder.Link = [string]$Page.'@odata.deltaLink'
                        $S.FolderIndex++
                    }
                } else {
                    $Warnings.Add("Too many items failed in $Path; this part of the folder is backed up again on the next run.")
                    $S.FolderIndex++
                }
            }
        }
    }

    foreach ($R in $ToRemove) {
        $Folder = $ById[$R.FolderId]
        $Key = 'items/{0}/{1}' -f $R.FolderId.Replace('/', '-').Replace('+', '_'), $R.Id.Replace('/', '-').Replace('+', '_')
        try {
            $null = Remove-CIPPCloudBackupItem -Context $Context -ItemKey "$Key.fts"
            if ($Folder.Type -like 'IPF.Note*') { $null = Remove-CIPPCloudBackupItem -Context $Context -ItemKey "$Key.eml" }
        } catch {
            $Warnings.Add("Removing deleted item $($R.Id) failed: $($_.Exception.Message)")
            if ($R.Attempts + 1 -lt $MaxAttempts) { $R.Attempts++; $Retry.Add($R) }
            continue
        }
        $Deleted++
        $Type = if ($Folder.Type -like 'IPF.Appointment*') { 'event' } elseif ($Folder.Type -like 'IPF.Contact*') { 'contact' } else { 'message' }
        $IndexEntries.Add([pscustomobject]@{ k = "$Key.fts"; p = $Paths[$R.FolderId]; n = $null; t = $Type; s = $null; m = $null; v = $null; d = $true; x = [ordered]@{ id = $R.Id } })
    }

    $S.Folders = @(foreach ($F in $Folders) { $F })
    $S.Removals = @(foreach ($R in $Removals) { $R })
    $S.Retry = @(foreach ($R in $Retry) { $R })

    [pscustomobject]@{
        State        = $S
        Done         = $Done
        Items        = $Items
        Bytes        = $Bytes
        Deleted      = $Deleted
        Warnings     = $Warnings.ToArray()
        IndexEntries = $IndexEntries.ToArray()
    }
}
