function Invoke-CIPPCloudBackupExchangeRestoreStep {
    <#
    .SYNOPSIS
        Restores one bounded batch of backed-up mailbox items (mail, events, contacts and folders) into a mailbox, or plans it for a preview.
    .DESCRIPTION
        Returns { State; Done; Results; Bytes }. With Context.Apply false the target mailbox is only read.
        An item already in the target folder is one with the same internetMessageId (mail), or the same item id when
        restoring to the source mailbox's original folders; events and contacts restored anywhere else have no stable
        key and are always created. Skip leaves the existing item. Overwrite imports in update mode over the existing
        item (same item id, content replaced, nothing deleted). Copy imports a second item next to it; the export stream
        is opaque, so the copy keeps its original subject.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Context,

        $State
    )

    $BatchCount = 20
    $BatchBytes = 24MB
    $MaxAttempts = 3
    $Graph = 'https://graph.microsoft.com/beta'
    $Tenant = $Context.TenantFilter
    $Apply = [bool]$Context.Apply
    $OwnerPrefix = ([string]$Context.OwnerPrefix).TrimEnd('/') + '/'
    $TargetOwner = [string]$Context.Target.OwnerId
    if (-not $TargetOwner) { throw [System.ArgumentException]::new('A target mailbox is required.') }
    if ($Context.SourceRemoved -and $TargetOwner -eq [string]$Context.SourceOwnerId) {
        throw [System.ArgumentException]::new('The source mailbox no longer exists; restore it to another user.')
    }
    $SameMailbox = $TargetOwner -eq [string]$Context.SourceOwnerId
    $Original = $Context.Location -eq 'Original'
    $ConflictAction = if ($Context.ConflictAction -in @('Overwrite', 'Copy')) { [string]$Context.ConflictAction } else { 'Skip' }

    $S = @{
        Offset             = [int]$State.Offset
        MailboxId          = [string]$State.MailboxId
        RootId             = [string]$State.RootId
        RootName           = [string]$State.RootName
        RestoredFolderName = [string]$State.RestoredFolderName
    }
    if (-not $S.RestoredFolderName) {
        $S.RestoredFolderName = if ($Context.RestoredFolderName) { [string]$Context.RestoredFolderName } else { 'Restored {0}' -f [datetime]::UtcNow.ToString('yyyy-MM-dd HH:mm') }
    }
    $Folders = [System.Collections.Generic.Dictionary[string, hashtable]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($F in @($State.Folders)) {
        if ($null -ne $F -and $F.Path) { $Folders[[string]$F.Path] = @{ Path = [string]$F.Path; Id = [string]$F.Id; Created = [bool]$F.Created } }
    }

    $Results = [System.Collections.Generic.List[object]]::new()
    $Bytes = [long]0

    $Entries = @(Get-CIPPCloudBackupJobItemBatch -Context $Context -Offset $S.Offset -Count $BatchCount)
    if ($Entries.Count -eq 0) {
        $S.Folders = @(foreach ($F in $Folders.Values) { $F })
        return [pscustomobject]@{ State = $S; Done = $true; Results = @(); Bytes = $Bytes }
    }

    if (-not $S.MailboxId) {
        $Settings = New-GraphGetRequest -uri "$Graph/users/$TargetOwner/settings/exchange" -tenantid $Tenant -AsApp $true -noPagination $true
        if (-not $Settings.primaryMailboxId) { throw [System.Management.Automation.ItemNotFoundException]::new("No mailbox found for $($Context.Target.UserPrincipalName ?? $TargetOwner).") }
        $S.MailboxId = [string]$Settings.primaryMailboxId
    }
    $MailboxPath = "/admin/exchange/mailboxes/$($S.MailboxId)"

    $Children = [System.Collections.Generic.Dictionary[string, object[]]]::new([System.StringComparer]::Ordinal)
    if (-not $S.RootId) {
        $TopLevel = @(New-GraphGetRequest -uri "$Graph$MailboxPath/folders?`$select=id,displayName,parentFolderId,type" -tenantid $Tenant -AsApp $true)
        $Children[''] = $TopLevel
        foreach ($F in $TopLevel) { if ($F.parentFolderId) { $S.RootId = [string]$F.parentFolderId; break } }
        if ($S.RootId) {
            try {
                $Root = New-GraphGetRequest -uri "$Graph$MailboxPath/folders/$([uri]::EscapeDataString($S.RootId))?`$select=id,displayName" -tenantid $Tenant -AsApp $true -noPagination $true
                $S.RootName = [string]$Root.displayName
            } catch {
                $S.RootName = ''
            }
        }
    }

    $Planned = [System.Collections.Generic.List[hashtable]]::new()
    $Taken = 0
    $TakenBytes = [long]0
    foreach ($Entry in $Entries) {
        if ($Taken -gt 0 -and $TakenBytes + [long]$Entry.Size -gt $BatchBytes) { break }
        $Taken++
        $TakenBytes += [long]$Entry.Size

        $Type = [string]$Entry.Type
        $Plan = @{ Entry = $Entry; Type = $Type; Row = $null }
        $SourcePath = [string]$Entry.Path
        if ($Type -eq 'folder') {
            $SourcePath = if ($SourcePath) { "$SourcePath/$($Entry.Name)" } else { [string]$Entry.Name }
            $Plan.Class = if ($Entry.Extra.type) { [string]$Entry.Extra.type } else { 'IPF.Note' }
        } elseif ($Type -in @('message', 'event', 'contact') -and ([string]$Entry.Key).EndsWith('.fts')) {
            $Plan.Class = switch ($Type) { 'event' { 'IPF.Appointment' } 'contact' { 'IPF.Contact' } default { 'IPF.Note' } }
        } else {
            $Plan.Row = @{ Action = 'NotRestorable'; Status = 'Skipped'; Message = 'This kind of item cannot be restored to a mailbox.'; TargetPath = $null }
            $Planned.Add($Plan)
            continue
        }

        $Segments = [System.Collections.Generic.List[string]]::new()
        foreach ($Segment in $SourcePath.Split('/')) { if ($Segment) { $Segments.Add($Segment) } }
        if ($Segments.Count -gt 0 -and ($Segments[0] -eq 'Top of Information Store' -or ($S.RootName -and $Segments[0] -eq $S.RootName))) { $Segments.RemoveAt(0) }
        if ($Type -eq 'folder' -and $Segments.Count -eq 0) {
            $Plan.Row = @{ Action = 'Skip'; Status = 'Skipped'; Message = 'The top folder of the mailbox already exists.'; TargetPath = $null }
            $Planned.Add($Plan)
            continue
        }
        if (-not $Original) { $Segments.Insert(0, $S.RestoredFolderName) }
        $Plan.Segments = $Segments.ToArray()
        $Plan.TargetPath = $Segments -join '/'
        $Planned.Add($Plan)
    }

    $FolderErrors = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($Plan in $Planned) {
        if ($Plan.Row -or $Plan.Segments.Count -eq 0) { continue }
        $ParentId = ''
        $Missing = $false
        for ($i = 0; $i -lt $Plan.Segments.Count; $i++) {
            $Path = $Plan.Segments[0..$i] -join '/'
            if ($FolderErrors.ContainsKey($Path)) { break }
            if ($Folders.ContainsKey($Path)) {
                $ParentId = $Folders[$Path].Id
                if (-not $ParentId) { $Missing = $true }
                continue
            }
            $Name = $Plan.Segments[$i]
            $Found = $null
            if (-not $Missing) {
                if (-not $Children.ContainsKey($ParentId)) {
                    $Uri = if ($ParentId) { "$Graph$MailboxPath/folders/$([uri]::EscapeDataString($ParentId))/childFolders?`$select=id,displayName,parentFolderId,type" } else { "$Graph$MailboxPath/folders?`$select=id,displayName,parentFolderId,type" }
                    try {
                        $Children[$ParentId] = @(New-GraphGetRequest -uri $Uri -tenantid $Tenant -AsApp $true)
                    } catch {
                        $FolderErrors[$Path] = "Reading the folders of the target mailbox failed: $($_.Exception.Message)"
                        break
                    }
                }
                foreach ($Child in $Children[$ParentId]) { if ([string]$Child.displayName -eq $Name) { $Found = $Child; break } }
            }
            if ($Found) {
                $Folders[$Path] = @{ Path = $Path; Id = [string]$Found.id; Created = $false }
                $ParentId = [string]$Found.id
                continue
            }
            if (-not $Apply) {
                $Folders[$Path] = @{ Path = $Path; Id = ''; Created = $true }
                $Missing = $true
                continue
            }
            $Class = if (-not $Original -and $i -eq 0) { 'IPF.Note' } else { $Plan.Class }
            $Url = if ($ParentId) { "$MailboxPath/folders/$([uri]::EscapeDataString($ParentId))/childFolders" } else { "$MailboxPath/folders" }
            $Response = $null
            try {
                $Response = @(New-GraphBulkRequest -tenantid $Tenant -asapp $true -Requests @(@{ id = 'folder'; method = 'POST'; url = $Url; body = @{ displayName = $Name; type = $Class }; headers = @{ 'Content-Type' = 'application/json' } }))[0]
            } catch {
                $FolderErrors[$Path] = "Creating folder $Path failed: $($_.Exception.Message)"
                break
            }
            if (([int]$Response.status) -ge 400 -or -not $Response.body.id) {
                $FolderErrors[$Path] = "Creating folder $Path failed: HTTP $($Response.status) $($Response.body.error.message)"
                break
            }
            $Folders[$Path] = @{ Path = $Path; Id = [string]$Response.body.id; Created = $true }
            $null = $Children.Remove($ParentId)
            $ParentId = [string]$Response.body.id
        }
    }

    $Lookups = [System.Collections.Generic.List[object]]::new()
    for ($n = 0; $n -lt $Planned.Count; $n++) {
        $Plan = $Planned[$n]
        if ($Plan.Row -or $Plan.Type -eq 'folder') { continue }
        $Plan.FolderId = if ($Plan.Segments.Count -eq 0) { $S.RootId } elseif ($Folders.ContainsKey($Plan.TargetPath)) { $Folders[$Plan.TargetPath].Id } else { '' }
        if (-not $Plan.FolderId) { continue }
        $ItemsUrl = "$MailboxPath/folders/$([uri]::EscapeDataString($Plan.FolderId))/items"
        $SourceId = [string]$Plan.Entry.Extra.id
        if ($SameMailbox -and $Original -and $SourceId) {
            $Lookups.Add(@{ id = "i$n"; method = 'GET'; url = "$ItemsUrl/$([uri]::EscapeDataString($SourceId))?`$select=id,changeKey" })
        }
        $MessageId = [string]$Plan.Entry.Extra.internetMessageId
        if ($Plan.Type -eq 'message' -and $MessageId) {
            # PidTagInternetMessageId: https://learn.microsoft.com/office/client-developer/outlook/mapi/pidtaginternetmessageid-canonical-property
            $Filter = [uri]::EscapeDataString("singleValueExtendedProperties/Any(ep: ep/id eq 'String 0x1035' and ep/value eq '$($MessageId.Replace("'", "''"))')")
            $Lookups.Add(@{ id = "m$n"; method = 'GET'; url = "$ItemsUrl`?`$filter=$Filter&`$select=id,changeKey&`$top=1" })
        }
    }

    $LookupResults = @{}
    if ($Lookups.Count -gt 0) {
        try {
            foreach ($Response in @(New-GraphBulkRequest -tenantid $Tenant -asapp $true -Requests $Lookups.ToArray() -NoPaginateIds @($Lookups.id))) {
                $LookupResults[[string]$Response.id] = $Response
            }
        } catch {
            $LookupError = $_.Exception.Message
            foreach ($Lookup in $Lookups) { $LookupResults[$Lookup.id] = @{ id = $Lookup.id; status = 500; body = @{ error = @{ message = $LookupError } } } }
        }
    }

    $ImportUrl = $null
    $SessionError = $null
    for ($n = 0; $n -lt $Planned.Count; $n++) {
        $Plan = $Planned[$n]
        $Entry = $Plan.Entry
        $Row = $Plan.Row
        $TargetPath = $Plan.TargetPath
        if (-not $Row -and $Plan.Segments.Count -gt 0) {
            for ($i = 0; $i -lt $Plan.Segments.Count; $i++) {
                $Path = $Plan.Segments[0..$i] -join '/'
                if ($FolderErrors.ContainsKey($Path)) { $Row = @{ Action = 'Create'; Status = 'Failed'; Message = $FolderErrors[$Path] }; break }
            }
        }
        if (-not $Row -and $Plan.Type -eq 'folder') {
            $Known = $Folders[$Plan.TargetPath]
            $Row = if (-not $Known.Created) {
                @{ Action = 'Skip'; Status = 'Skipped'; Message = 'The folder already exists.' }
            } elseif ($Apply) {
                @{ Action = 'Create'; Status = 'Succeeded'; Message = 'Folder created.' }
            } else {
                @{ Action = 'Create'; Status = 'Planned'; Message = 'The folder will be created.' }
            }
        }
        if (-not $Row) {
            $Existing = $null
            $CheckError = $null
            foreach ($Id in @("i$n", "m$n")) {
                if (-not $LookupResults.ContainsKey($Id)) { continue }
                $Response = $LookupResults[$Id]
                $Status = [int]$Response.status
                if ($Status -eq 404 -and $Id.StartsWith('i')) { continue }
                if ($Status -ge 400) { $CheckError = "Checking the target folder for an existing copy failed: HTTP $Status $($Response.body.error.message)"; break }
                $Found = if ($Id.StartsWith('i')) { $Response.body } else { @($Response.body.value)[0] }
                if ($Found.id) { $Existing = $Found; break }
            }
            if ($CheckError) {
                $Row = @{ Action = 'Create'; Status = 'Failed'; Message = $CheckError }
            } elseif (-not $Plan.FolderId -and $Plan.Segments.Count -eq 0) {
                $Row = @{ Action = 'Create'; Status = 'Failed'; Message = 'The top folder of the target mailbox could not be found.' }
            } else {
                $Action = if (-not $Existing) { 'Create' } else { $ConflictAction }
                $Message = switch ($Action) {
                    'Skip' { 'The item already exists in the target folder and was left as it is.' }
                    'Overwrite' { 'The existing item is replaced with the backed-up version.' }
                    'Copy' { 'A copy is added next to the existing item.' }
                    default { if ($Plan.FolderId) { 'The item will be created.' } else { 'The item will be created in a new folder.' } }
                }
                $Row = @{ Action = $Action; Status = if ($Action -eq 'Skip') { 'Skipped' } else { 'Planned' }; Message = $Message; Existing = $Existing }
            }
        }

        if ($Apply -and $Row.Status -eq 'Planned') {
            if (-not $ImportUrl -and -not $SessionError) {
                try {
                    $Session = New-GraphPOSTRequest -uri "$Graph$MailboxPath/createImportSession" -tenantid $Tenant -AsApp $true -type POST -body '{}'
                    Assert-CIPPMicrosoftHost -Uri ([string]$Session.importUrl)
                    $ImportUrl = [string]$Session.importUrl
                } catch {
                    $SessionError = "Starting the mailbox import failed: $($_.Exception.Message)"
                }
            }
            if ($SessionError) {
                $Row.Status = 'Failed'
                $Row.Message = $SessionError
            } else {
                $Raw = [System.IO.MemoryStream]::new()
                $Plain = $null
                try {
                    $Received = Receive-CIPPCloudBackupObjectStream -Destination $Context.Destination -Key ($OwnerPrefix + ([string]$Entry.Key).TrimStart('/')) -VersionId ([string]$Entry.VersionId) -OutStream $Raw
                    if ($null -eq $Received) { throw 'The backed-up copy of this item is no longer in storage.' }
                    $Magic = if ($Raw.Length -ge 8) { [System.Text.Encoding]::ASCII.GetString($Raw.GetBuffer(), 0, 8) } else { '' }
                    if ($Magic -eq 'CIPPENC2') {
                        $Raw.Position = 0
                        $Plain = [System.IO.MemoryStream]::new()
                        $null = Unprotect-CIPPCloudBackupStream -InputStream $Raw -OutputStream $Plain
                        $Raw.Dispose()
                    } elseif ($Magic -eq 'CIPPENC1') {
                        $Decrypted = Unprotect-CIPPCloudBackupData -Bytes $Raw.ToArray()
                        $Raw.Dispose()
                        $Plain = [System.IO.MemoryStream]::new($Decrypted, 0, $Decrypted.Length, $false, $true)
                    } else {
                        $Plain = $Raw
                    }
                    $Length = $Plain.Length
                    $Fields = [ordered]@{ FolderId = $Plan.FolderId; Mode = 'create' }
                    if ($Row.Action -eq 'Overwrite') {
                        $Fields.Mode = 'update'
                        $Fields.ItemId = [string]$Row.Existing.id
                        $Fields.ChangeKey = [string]$Row.Existing.changeKey
                    }
                    $Json = $Fields | ConvertTo-Json -Compress
                    $Body = '{"Data":"' + [Convert]::ToBase64String($Plain.GetBuffer(), 0, [int]$Length) + '",' + $Json.Substring(1)
                    $Plain.Dispose()
                    $Plain = $null

                    $Imported = $false
                    $Renewed = $false
                    for ($Attempt = 1; -not $Imported; $Attempt++) {
                        try {
                            $null = Invoke-CIPPRestMethod -Uri $ImportUrl -Method POST -Body $Body -ContentType 'application/json' -TimeoutSec 600
                            $Imported = $true
                        } catch {
                            $Status = 0
                            if ($_.Exception.Response) { $Status = [int]$_.Exception.Response.StatusCode }
                            $Detail = $_.ErrorDetails.Message
                            if ($Detail) {
                                try { $Detail = [string](ConvertFrom-Json -InputObject $Detail).error.message } catch { $null = $_ }
                            }
                            if (-not $Detail) { $Detail = $_.Exception.Message }
                            if ($Status -eq 401 -and -not $Renewed) {
                                $Renewed = $true
                                $Session = New-GraphPOSTRequest -uri "$Graph$MailboxPath/createImportSession" -tenantid $Tenant -AsApp $true -type POST -body '{}'
                                Assert-CIPPMicrosoftHost -Uri ([string]$Session.importUrl)
                                $ImportUrl = [string]$Session.importUrl
                                continue
                            }
                            if ($Status -in @(429, 503) -and $Attempt -lt $MaxAttempts) {
                                $Wait = $_.Exception.Response.Headers['Retry-After'] -as [int]
                                if (-not $Wait -or $Wait -lt 1) { $Wait = [Math]::Pow(2, $Attempt) }
                                Start-Sleep -Seconds ([Math]::Min($Wait, 60))
                                continue
                            }
                            throw "Importing the item failed: $(if ($Status) { "HTTP $Status " })$Detail"
                        }
                    }
                    $Bytes += $Length
                    $Row.Status = 'Succeeded'
                    $Row.Message = switch ($Row.Action) {
                        'Overwrite' { 'The existing item was replaced with the backed-up version.' }
                        'Copy' { 'A copy was added next to the existing item.' }
                        default { 'Restored.' }
                    }
                } catch {
                    $Row.Status = 'Failed'
                    $Row.Message = $_.Exception.Message
                } finally {
                    $Raw.Dispose()
                    if ($Plain) { $Plain.Dispose() }
                    $Body = $null
                }
            }
        }

        $Results.Add([pscustomobject]@{
                Key        = $Entry.Key
                Name       = $Entry.Name
                Path       = $Entry.Path
                Type       = $Entry.Type
                Action     = $Row.Action
                Status     = $Row.Status
                Message    = $Row.Message
                TargetPath = if ($null -ne $TargetPath) { if ($TargetPath) { $TargetPath } else { $S.RootName } } else { $null }
            })
    }

    $S.Offset += $Taken
    $S.Folders = @(foreach ($F in $Folders.Values) { $F })
    [pscustomobject]@{
        State   = $S
        Done    = $Entries.Count -lt $BatchCount -and $Taken -eq $Entries.Count
        Results = $Results.ToArray()
        Bytes   = $Bytes
    }
}
