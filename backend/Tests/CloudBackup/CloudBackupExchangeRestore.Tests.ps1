BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup'
    Add-Type -Path (Join-Path $BackendRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    function Get-CIPPCloudBackupJobItemBatch { param($Context, $Offset, $Count) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, $noPagination, [switch]$SkipValueExtraction, $extraHeaders) }
    function New-GraphBulkRequest { param($tenantid, $asapp, $Requests, $NoPaginateIds) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $AsApp, $type, $body) }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Body, $ContentType, $TimeoutSec) }
    function Receive-CIPPCloudBackupObjectStream { param($Destination, $Key, $VersionId, $OutStream) }
    function Get-CIPPCloudBackupKey { param($KeyId) }
    . (Join-Path $BackendRoot 'Modules/CIPPCore/Public/GraphHelper/Assert-CIPPMicrosoftHost.ps1')
    foreach ($Name in 'Invoke-CIPPCloudBackupExchangeRestoreStep', 'Unprotect-CIPPCloudBackupStream', 'Unprotect-CIPPCloudBackupStreamBlock', 'Unprotect-CIPPCloudBackupData', 'Protect-CIPPCloudBackupData', 'Read-CIPPCloudBackupStreamBlock') {
        . (Join-Path $Folder "$Name.ps1")
    }

    $script:Graph = 'https://graph.microsoft.com/beta'
    $script:KeyId = [guid]::NewGuid().ToString()
    $script:Key = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $script:ImportUrl = "https://outlook.office365.com/api/gbeta/Mailboxes('MBX:target')/importItem?authtoken=abc"

    function script:New-Entry {
        param([string]$Id, [string]$Type = 'message', [string]$Path = 'Top of Information Store/Inbox', [long]$Size = 100, [string]$MessageId, [string]$Name)
        $Extra = [ordered]@{ id = $Id }
        if ($Type -eq 'message') { $Extra.internetMessageId = if ($MessageId) { $MessageId } else { "<$Id@contoso.com>" } }
        if ($Type -eq 'folder') {
            $Extra.type = 'IPF.Note'
            return [pscustomobject]@{ Key = "items/$Id/"; Path = $Path; Name = $Name; Type = 'folder'; Size = $null; Modified = $null; VersionId = $null; Deleted = $false; Extra = [pscustomobject]$Extra; RunStamp = '20261101T000000Z' }
        }
        [pscustomobject]@{ Key = "items/F/$Id.fts"; Path = $Path; Name = "Subject $Id"; Type = $Type; Size = $Size; Modified = '2026-10-01T00:00:00Z'; VersionId = "v-$Id"; Deleted = $false; Extra = [pscustomobject]$Extra; RunStamp = '20261101T000000Z' }
    }

    function script:New-Context {
        param([bool]$Apply = $false, [string]$Location = 'RestoredFolder', [string]$Conflict = 'Skip', [string]$TargetOwner = 'source-user', [bool]$Removed = $false)
        [pscustomobject]@{
            JobId = 'job-1'; PolicyId = 'policy'; TenantId = 'tid'; TenantFilter = 'contoso.onmicrosoft.com'; Workload = 'exchange'
            SourceOwnerId = 'source-user'; SourceOwnerType = 'UserMailbox'; SourceRemoved = $Removed
            Target = @{ OwnerId = $TargetOwner; OwnerType = 'UserMailbox'; UserPrincipalName = "$TargetOwner@contoso.com" }
            Location = $Location; RestoredFolderName = 'Restored 2026-11-20 10:00'; ConflictAction = $Conflict
            AsOf = '20261101T000000Z'; RunStamp = '20261101T000000Z'; Destination = [pscustomobject]@{ Provider = 'AzureBlob' }
            KeyId = $null; Key = $null; OwnerPrefix = 'policy/customer/exchange/source-user/'; Apply = $Apply
        }
    }

    function script:Invoke-Restore {
        param($Context, [int]$MaxSteps = 20)
        $State = $null
        $Rows = [System.Collections.Generic.List[object]]::new()
        $Steps = 0
        do {
            $Result = Invoke-CIPPCloudBackupExchangeRestoreStep -Context $Context -State $State
            $State = $Result.State | ConvertTo-Json -Depth 10 | ConvertFrom-Json -AsHashtable
            foreach ($R in $Result.Results) { $Rows.Add($R) }
            $Steps++
        } until ($Result.Done -or $Steps -ge $MaxSteps)
        [pscustomobject]@{ Rows = $Rows.ToArray(); Steps = $Steps; State = $State; Done = $Result.Done }
    }
}

Describe 'Invoke-CIPPCloudBackupExchangeRestoreStep' {
    BeforeEach {
        $script:Entries = [System.Collections.Generic.List[object]]::new()
        $script:Stored = @{}
        $script:MailboxFolders = [System.Collections.Generic.List[hashtable]]::new()
        $script:MailboxFolders.Add(@{ id = 'INBOX'; displayName = 'Inbox'; parentFolderId = 'ROOT'; type = 'IPF.Note' })
        $script:MailboxFolders.Add(@{ id = 'CAL'; displayName = 'Calendar'; parentFolderId = 'ROOT'; type = 'IPF.Appointment' })
        $script:ExistingIds = @{}
        $script:ExistingMessageIds = @{}
        $script:BulkRequests = [System.Collections.Generic.List[object]]::new()
        $script:Imports = [System.Collections.Generic.List[object]]::new()
        $script:ImportFailures = @{}
        $script:Throttle = 0
        $script:BatchCalls = [System.Collections.Generic.List[object]]::new()
        $script:FolderSeq = 0

        Mock Get-CIPPCloudBackupJobItemBatch {
            $script:BatchCalls.Add(@{ Offset = $Offset; Count = $Count })
            $End = [Math]::Min($Offset + $Count, $script:Entries.Count)
            @(for ($i = $Offset; $i -lt $End; $i++) { $script:Entries[$i] })
        }
        Mock New-GraphGetRequest {
            if ($uri -like '*/settings/exchange') { return @{ primaryMailboxId = "MBX:$(($uri -split '/')[-3])" } }
            if ($uri -match '/folders/ROOT\?') { return @{ id = 'ROOT'; displayName = 'Top of Information Store' } }
            if ($uri -match '/folders/([^/?]+)/childFolders') {
                $Parent = [uri]::UnescapeDataString($Matches[1])
                return @(foreach ($F in $script:MailboxFolders) { if ($F.parentFolderId -eq $Parent) { $F } })
            }
            if ($uri -match '/folders\?') { return @(foreach ($F in $script:MailboxFolders) { if ($F.parentFolderId -eq 'ROOT') { $F } }) }
            throw "Unexpected GET $uri"
        }
        Mock New-GraphBulkRequest {
            foreach ($Request in $Requests) {
                $script:BulkRequests.Add($Request)
                if ($Request.method -eq 'POST') {
                    $script:FolderSeq++
                    $Parent = if ($Request.url -match '/folders/([^/]+)/childFolders$') { [uri]::UnescapeDataString($Matches[1]) } else { 'ROOT' }
                    $New = @{ id = "NEW$($script:FolderSeq)"; displayName = $Request.body.displayName; parentFolderId = $Parent; type = $Request.body.type }
                    $script:MailboxFolders.Add($New)
                    @{ id = $Request.id; status = 201; body = $New }
                } elseif ($Request.url -match '/folders/([^/]+)/items/([^/?]+)\?') {
                    $Key = '{0}|{1}' -f [uri]::UnescapeDataString($Matches[1]), [uri]::UnescapeDataString($Matches[2])
                    if ($script:ExistingIds.ContainsKey($Key)) { @{ id = $Request.id; status = 200; body = $script:ExistingIds[$Key] } }
                    else { @{ id = $Request.id; status = 404; body = @{ error = @{ message = 'Not found' } } } }
                } elseif ($Request.url -match '/folders/([^/]+)/items\?\$filter=([^&]+)') {
                    $FolderId = [uri]::UnescapeDataString($Matches[1])
                    $Filter = [uri]::UnescapeDataString($Matches[2])
                    $null = $Filter -match "ep/value eq '(.*)'\)$"
                    $Value = $Matches[1].Replace("''", "'")
                    $Found = $script:ExistingMessageIds["$FolderId|$Value"]
                    @{ id = $Request.id; status = 200; body = @{ value = @(if ($Found) { $Found }) } }
                } else {
                    throw "Unexpected batch request $($Request.url)"
                }
            }
        }
        Mock New-GraphPOSTRequest { @{ importUrl = $script:ImportUrl; expirationDateTime = '2026-11-20T12:00:00Z' } }
        Mock Invoke-CIPPRestMethod {
            $Parsed = $Body | ConvertFrom-Json
            $Item = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Parsed.Data))
            if ($script:Throttle -gt 0) {
                $script:Throttle--
                $Headers = [System.Collections.Generic.Dictionary[string, string[]]]::new()
                $Headers['Retry-After'] = @('7')
                throw [CIPP.CIPPHttpRequestException]::new('Too many requests', 429, $Headers, '')
            }
            if ($script:ImportFailures.ContainsKey($Item)) {
                $Record = [System.Management.Automation.ErrorRecord]::new([CIPP.CIPPHttpRequestException]::new('Bad request', 400, $null, ''), 'x', 'InvalidOperation', $null)
                $Record.ErrorDetails = [System.Management.Automation.ErrorDetails]::new((@{ error = @{ message = $script:ImportFailures[$Item] } } | ConvertTo-Json))
                throw $Record
            }
            $script:Imports.Add([pscustomobject]@{ Uri = $Uri; FolderId = $Parsed.FolderId; Mode = $Parsed.Mode; ItemId = $Parsed.ItemId; ChangeKey = $Parsed.ChangeKey; Content = $Item })
            @{ itemId = "new-$Item"; changeKey = 'ck' }
        }
        Mock Receive-CIPPCloudBackupObjectStream {
            if (-not $script:Stored.ContainsKey($Key)) { return $null }
            $Data = $script:Stored[$Key]
            $OutStream.Write($Data, 0, $Data.Length)
            [pscustomobject]@{ Key = $Key; VersionId = $VersionId; Bytes = $Data.Length }
        }
        Mock Get-CIPPCloudBackupKey { [byte[]]$script:Key.Clone() }
        Mock Start-Sleep {}

        function script:Add-Item {
            param($Entry, [string]$Encryption = 'None')
            $script:Entries.Add($Entry)
            $Plain = [Text.Encoding]::UTF8.GetBytes("FTS:$($Entry.Extra.id)")
            $Data = switch ($Encryption) {
                'CIPPENC1' { Protect-CIPPCloudBackupData -Bytes $Plain -KeyId $script:KeyId -Key $script:Key }
                'CIPPENC2' {
                    $Reader = @{ Stream = [System.IO.MemoryStream]::new($Plain); KeyId = $script:KeyId; Key = $script:Key; ChunkSize = 4 }
                    $Out = [System.IO.MemoryStream]::new()
                    do { $Block = Read-CIPPCloudBackupStreamBlock -Reader $Reader -Size 64; $Out.Write($Block, 0, $Block.Length) } while ($Block.Length -eq 64)
                    $Out.ToArray()
                }
                default { $Plain }
            }
            if ($null -ne $Entry.Size) { $script:Stored["policy/customer/exchange/source-user/$($Entry.Key)"] = [byte[]]$Data }
        }
    }

    It 'makes no writes in preview and plans items under the restored folder' {
        Add-Item (New-Entry -Id 'm1')
        Add-Item (New-Entry -Id 'm2' -Path 'Top of Information Store/Inbox/Projects')
        $Run = Invoke-Restore (New-Context -Apply $false)

        $Run.Done | Should -BeTrue
        $Run.Rows.Count | Should -Be 2
        $Run.Rows.Action | Should -Be @('Create', 'Create')
        $Run.Rows.Status | Should -Be @('Planned', 'Planned')
        $Run.Rows.TargetPath | Should -Be @('Restored 2026-11-20 10:00/Inbox', 'Restored 2026-11-20 10:00/Inbox/Projects')
        @($script:BulkRequests | Where-Object { $_.method -ne 'GET' }).Count | Should -Be 0
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        Should -Invoke Invoke-CIPPRestMethod -Times 0 -Exactly
        Should -Invoke Receive-CIPPCloudBackupObjectStream -Times 0 -Exactly
    }

    It 'previews conflicts in original folders without writing' {
        Add-Item (New-Entry -Id 'm1')
        $script:ExistingIds['INBOX|m1'] = @{ id = 'm1'; changeKey = 'CK1' }
        $Run = Invoke-Restore (New-Context -Apply $false -Location 'Original' -Conflict 'Overwrite')
        $Run.Rows[0].Action | Should -Be 'Overwrite'
        $Run.Rows[0].Status | Should -Be 'Planned'
        $Run.Rows[0].TargetPath | Should -Be 'Inbox'
        @($script:BulkRequests | Where-Object { $_.method -ne 'GET' }).Count | Should -Be 0
        Should -Invoke Invoke-CIPPRestMethod -Times 0 -Exactly
    }

    It 'creates the restored folder tree and imports decrypted items into it' {
        Add-Item (New-Entry -Id 'm1') -Encryption 'CIPPENC2'
        Add-Item (New-Entry -Id 'm2' -Path 'Top of Information Store/Inbox/Projects') -Encryption 'CIPPENC1'
        Add-Item (New-Entry -Id 'e1' -Type 'event' -Path 'Top of Information Store/Calendar')
        $Run = Invoke-Restore (New-Context -Apply $true)

        $Run.Rows.Status | Should -Be @('Succeeded', 'Succeeded', 'Succeeded')
        $Created = @($script:BulkRequests | Where-Object { $_.method -eq 'POST' })
        $Created.body.displayName | Should -Be @('Restored 2026-11-20 10:00', 'Inbox', 'Projects', 'Calendar')
        $Created[0].url | Should -Be '/admin/exchange/mailboxes/MBX:source-user/folders'
        $Created[1].url | Should -Be '/admin/exchange/mailboxes/MBX:source-user/folders/NEW1/childFolders'
        $Created[0].body.type | Should -Be 'IPF.Note'
        $Created[3].body.type | Should -Be 'IPF.Appointment'
        $script:Imports.Content | Should -Be @('FTS:m1', 'FTS:m2', 'FTS:e1')
        $script:Imports.FolderId | Should -Be @('NEW2', 'NEW3', 'NEW4')
        $script:Imports.Mode | Should -Be @('create', 'create', 'create')
        $script:Imports[0].Uri | Should -Be $script:ImportUrl
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -eq "$Graph/admin/exchange/mailboxes/MBX:source-user/createImportSession" }
    }

    It 'skips, overwrites in place or copies an item that already exists in its original folder' -ForEach @(
        @{ Conflict = 'Skip'; Action = 'Skip'; Status = 'Skipped'; Imports = 0; Mode = $null }
        @{ Conflict = 'Overwrite'; Action = 'Overwrite'; Status = 'Succeeded'; Imports = 1; Mode = 'update' }
        @{ Conflict = 'Copy'; Action = 'Copy'; Status = 'Succeeded'; Imports = 1; Mode = 'create' }
    ) {
        Add-Item (New-Entry -Id 'm1')
        Add-Item (New-Entry -Id 'm2')
        $script:ExistingIds['INBOX|m1'] = @{ id = 'm1'; changeKey = 'CK1' }
        $Run = Invoke-Restore (New-Context -Apply $true -Location 'Original' -Conflict $Conflict)

        $Run.Rows[0].Action | Should -Be $Action
        $Run.Rows[0].Status | Should -Be $Status
        $Run.Rows[1].Action | Should -Be 'Create'
        @($script:BulkRequests | Where-Object { $_.method -eq 'POST' }).Count | Should -Be 0
        @($script:Imports | Where-Object { $_.Content -eq 'FTS:m1' }).Count | Should -Be $Imports
        if ($Mode) {
            $Import = @($script:Imports | Where-Object { $_.Content -eq 'FTS:m1' })[0]
            $Import.Mode | Should -Be $Mode
            $Import.FolderId | Should -Be 'INBOX'
            if ($Mode -eq 'update') {
                $Import.ItemId | Should -Be 'm1'
                $Import.ChangeKey | Should -Be 'CK1'
            } else {
                $Import.ItemId | Should -BeNullOrEmpty
            }
        }
    }

    It 'detects mail already in another user''s mailbox by internetMessageId' {
        Add-Item (New-Entry -Id 'm1' -MessageId "<o'brien@contoso.com>")
        Add-Item (New-Entry -Id 'e1' -Type 'event' -Path 'Top of Information Store/Calendar')
        $script:ExistingMessageIds["INBOX|<o'brien@contoso.com>"] = @{ id = 'X1'; changeKey = 'CKX' }
        $Run = Invoke-Restore (New-Context -Apply $true -Location 'Original' -Conflict 'Overwrite' -TargetOwner 'other-user')

        $Run.Rows.Action | Should -Be @('Overwrite', 'Create')
        $script:Imports[0].ItemId | Should -Be 'X1'
        $script:Imports[0].Mode | Should -Be 'update'
        $script:Imports[1].FolderId | Should -Be 'CAL'
        @($script:BulkRequests | Where-Object { $_.url -match '/items/' -and $_.url -notmatch 'filter' }).Count | Should -Be 0
        @($script:BulkRequests | Where-Object { [uri]::UnescapeDataString($_.url) -like "*String 0x1035*o''brien*" }).Count | Should -Be 1
        Should -Invoke New-GraphGetRequest -ParameterFilter { $uri -eq "$Graph/users/other-user/settings/exchange" }
    }

    It 'restores a removed owner''s mailbox to another user and refuses the removed owner as target' {
        Add-Item (New-Entry -Id 'm1')
        { Invoke-CIPPCloudBackupExchangeRestoreStep -Context (New-Context -Apply $true -Removed $true) -State $null } | Should -Throw -ExceptionType ([System.ArgumentException])
        $Run = Invoke-Restore (New-Context -Apply $true -Removed $true -TargetOwner 'other-user')
        $Run.Rows[0].Status | Should -Be 'Succeeded'
        Should -Invoke Receive-CIPPCloudBackupObjectStream -ParameterFilter { $Key -eq 'policy/customer/exchange/source-user/items/F/m1.fts' -and $VersionId -eq 'v-m1' }
    }

    It 'isolates failures per item' {
        Add-Item (New-Entry -Id 'm1')
        Add-Item (New-Entry -Id 'm2')
        Add-Item (New-Entry -Id 'm3')
        $script:Stored.Remove('policy/customer/exchange/source-user/items/F/m3.fts')
        $script:ImportFailures['FTS:m1'] = 'The item is corrupt.'
        $Run = Invoke-Restore (New-Context -Apply $true -Location 'Original')

        $Run.Rows.Status | Should -Be @('Failed', 'Succeeded', 'Failed')
        $Run.Rows[0].Message | Should -BeLike '*HTTP 400 The item is corrupt.*'
        $Run.Rows[2].Message | Should -BeLike '*no longer in storage*'
    }

    It 'waits for Retry-After when the import is throttled' {
        Add-Item (New-Entry -Id 'm1')
        $script:Throttle = 1
        $Run = Invoke-Restore (New-Context -Apply $true -Location 'Original')
        $Run.Rows[0].Status | Should -Be 'Succeeded'
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
    }

    It 'gives up on an item after repeated throttling' {
        Add-Item (New-Entry -Id 'm1')
        $script:Throttle = 10
        $Run = Invoke-Restore (New-Context -Apply $true -Location 'Original')
        $Run.Rows[0].Status | Should -Be 'Failed'
        $Run.Rows[0].Message | Should -BeLike '*HTTP 429*'
    }

    It 'fails items in a folder that cannot be created and keeps going' {
        Add-Item (New-Entry -Id 'm1' -Path 'Top of Information Store/Inbox/Broken')
        Add-Item (New-Entry -Id 'm2')
        Mock New-GraphBulkRequest -ParameterFilter { $Requests[0].method -eq 'POST' } { @{ id = 'folder'; status = 400; body = @{ error = @{ message = 'Folder name is invalid' } } } }
        $Run = Invoke-Restore (New-Context -Apply $true -Location 'Original')
        $Run.Rows.Status | Should -Be @('Failed', 'Succeeded')
        $Run.Rows[0].Message | Should -BeLike '*Inbox/Broken*Folder name is invalid*'
    }

    It 'processes items in bounded steps and resumes from the saved offset' {
        for ($i = 1; $i -le 25; $i++) { Add-Item (New-Entry -Id "m$i") }
        $Run = Invoke-Restore (New-Context -Apply $true)
        $Run.Steps | Should -Be 2
        $Run.Rows.Count | Should -Be 25
        $script:BatchCalls.Offset | Should -Be @(0, 20)
        @($script:BulkRequests | Where-Object { $_.method -eq 'POST' }).Count | Should -Be 2
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/settings/exchange' }
    }

    It 'keeps a step to one large item' {
        Add-Item (New-Entry -Id 'big1' -Size 20MB)
        Add-Item (New-Entry -Id 'big2' -Size 20MB)
        $Run = Invoke-Restore (New-Context -Apply $true)
        $Run.Steps | Should -Be 2
        $Run.Rows.Status | Should -Be @('Succeeded', 'Succeeded')
    }

    It 'recreates folder entries and reports existing ones' {
        Add-Item (New-Entry -Id 'f1' -Type 'folder' -Path 'Top of Information Store/Inbox' -Name 'Archive 2024')
        Add-Item (New-Entry -Id 'f2' -Type 'folder' -Path 'Top of Information Store' -Name 'Inbox')
        Add-Item (New-Entry -Id 'root' -Type 'folder' -Path '' -Name 'Top of Information Store')
        $Preview = Invoke-Restore (New-Context -Apply $false -Location 'Original')
        $Preview.Rows.Action | Should -Be @('Create', 'Skip', 'Skip')
        $Preview.Rows.Status | Should -Be @('Planned', 'Skipped', 'Skipped')

        $Run = Invoke-Restore (New-Context -Apply $true -Location 'Original')
        $Run.Rows.Status | Should -Be @('Succeeded', 'Skipped', 'Skipped')
        @($script:BulkRequests | Where-Object { $_.method -eq 'POST' }).body.displayName | Should -Be @('Archive 2024')
        Should -Invoke Invoke-CIPPRestMethod -Times 0 -Exactly
    }

    It 'marks items that are not mailbox items as not restorable' {
        $script:Entries.Add([pscustomobject]@{ Key = 'items/F/x.eml'; Path = 'Inbox'; Name = 'x'; Type = 'message'; Size = 1; VersionId = 'v'; Extra = @{ id = 'x' } })
        $script:Entries.Add([pscustomobject]@{ Key = 'files/a.txt'; Path = ''; Name = 'a.txt'; Type = 'file'; Size = 1; VersionId = 'v'; Extra = $null })
        $Run = Invoke-Restore (New-Context -Apply $true)
        $Run.Rows.Action | Should -Be @('NotRestorable', 'NotRestorable')
        Should -Invoke Invoke-CIPPRestMethod -Times 0 -Exactly
    }

    It 'refuses an import URL outside Microsoft' {
        Add-Item (New-Entry -Id 'm1')
        Mock New-GraphPOSTRequest { @{ importUrl = 'https://evil.example.com/importItem' } }
        $Run = Invoke-Restore (New-Context -Apply $true -Location 'Original')
        $Run.Rows[0].Status | Should -Be 'Failed'
        Should -Invoke Invoke-CIPPRestMethod -Times 0 -Exactly
    }
}
