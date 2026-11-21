BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup'
    Add-Type -Path (Join-Path $BackendRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    function Get-CIPPCloudBackupKey { param($KeyId) }
    function Get-CIPPCloudBackupJobItemBatch { param($Context, $Offset, $Count) }
    function Get-CIPPCloudBackupObjectVersionList { param($Destination, $Prefix) }
    function Receive-CIPPCloudBackupObjectStream { param($Destination, $Key, $VersionId, $OutStream) }
    function Set-CIPPCloudBackupObject { param($Destination, $Key, $Body, $ContentType, $Metadata, [switch]$Confirm) }
    function Send-CIPPCloudBackupAzureObjectStream { param($Destination, $Key, $Reader, $FirstBlock, $ContentType, $Metadata) }
    function Send-CIPPCloudBackupS3ObjectStream { param($Destination, $Key, $Reader, $FirstBlock, $ContentType, $Metadata) }
    foreach ($Name in 'Send-CIPPCloudBackupObjectStream', 'Read-CIPPCloudBackupStreamBlock', 'Protect-CIPPCloudBackupStream', 'Unprotect-CIPPCloudBackupStream', 'Unprotect-CIPPCloudBackupStreamBlock', 'Protect-CIPPCloudBackupData', 'Unprotect-CIPPCloudBackupData', 'Get-CIPPCloudBackupExportStream', 'Invoke-CIPPCloudBackupExport') {
        . (Join-Path $Folder "$Name.ps1")
    }

    $script:KeyId = [guid]::NewGuid().ToString()
    $script:Key = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $script:Prefix = 'p1/tid/exchange/owner1/'

    function Protect-Bytes {
        param([byte[]]$Bytes)
        $Out = [System.IO.MemoryStream]::new()
        $null = Protect-CIPPCloudBackupStream -InputStream ([System.IO.MemoryStream]::new($Bytes)) -OutputStream $Out -KeyId $script:KeyId -Key $script:Key
        , $Out.ToArray()
    }

    function Set-Stored {
        param([string]$Key, [byte[]]$Bytes, [string]$VersionId = '', [string]$ContentType = 'application/octet-stream', [switch]$Encrypt)
        $script:Store["$Key|$VersionId"] = @{ Bytes = $(if ($Encrypt) { Protect-Bytes $Bytes } else { $Bytes }); ContentType = $ContentType }
    }

    function New-Entry {
        param($Key, $Path, $Name, $Type, $VersionId, $Extra, [switch]$Deleted)
        [pscustomobject]@{ Key = $Key; Path = $Path; Name = $Name; Type = $Type; Size = 10; Modified = '2026-11-01T00:00:00Z'; VersionId = $VersionId; Deleted = [bool]$Deleted; Extra = $Extra; RunStamp = '20261101T000000Z' }
    }

    function New-ExportContext {
        param($Workload = 'exchange', [switch]$Encrypted)
        [pscustomobject]@{
            JobId = 'job1'; PolicyId = 'p1'; TenantId = 'tid'; TenantFilter = 'contoso.onmicrosoft.com'; Workload = $Workload
            SourceOwnerId = 'owner1'; SourceOwnerName = 'Owner One'; RunStamp = '20261101T000000Z'; Destination = [pscustomobject]@{ Provider = 'AzureBlob' }
            KeyId = $(if ($Encrypted) { $script:KeyId }); Key = $(if ($Encrypted) { [byte[]]$script:Key.Clone() })
            OwnerPrefix = "p1/tid/$Workload/owner1/"
        }
    }

    function Read-Zip {
        param([byte[]]$Bytes)
        $Archive = [System.IO.Compression.ZipArchive]::new([System.IO.MemoryStream]::new($Bytes), [System.IO.Compression.ZipArchiveMode]::Read)
        $Result = [ordered]@{}
        foreach ($ZipEntry in $Archive.Entries) {
            $Stream = $ZipEntry.Open()
            $Copy = [System.IO.MemoryStream]::new()
            $Stream.CopyTo($Copy)
            $Stream.Dispose()
            $Result[$ZipEntry.FullName] = $Copy.ToArray()
        }
        $Archive.Dispose()
        $Result
    }

    function Get-Text { param([byte[]]$Bytes) [System.Text.Encoding]::UTF8.GetString($Bytes) }
}

Describe 'Invoke-CIPPCloudBackupExport' {
    BeforeEach {
        $script:Store = @{}
        $script:Entries = [System.Collections.Generic.List[object]]::new()
        $script:Uploaded = $null
        $script:ReceiveStreams = [System.Collections.Generic.List[string]]::new()
        Mock Get-CIPPCloudBackupKey { , ([byte[]]$script:Key.Clone()) }
        Mock Get-CIPPCloudBackupJobItemBatch {
            $Last = [Math]::Min($Offset + $Count, $script:Entries.Count)
            for ($i = $Offset; $i -lt $Last; $i++) { $script:Entries[$i] }
        }
        Mock Get-CIPPCloudBackupObjectVersionList { @() }
        Mock Receive-CIPPCloudBackupObjectStream {
            $script:ReceiveStreams.Add($OutStream.GetType().Name)
            $Stored = $script:Store["$Key|$VersionId"]
            if (-not $Stored) { return $null }
            $OutStream.Write($Stored.Bytes, 0, $Stored.Bytes.Length)
            [pscustomobject]@{ Key = $Key; VersionId = $VersionId; Bytes = $Stored.Bytes.Length; ContentType = $Stored.ContentType; Metadata = @{} }
        }
        Mock Send-CIPPCloudBackupObjectStream {
            $script:UploadStreamType = $Stream.GetType().Name
            $script:UploadArgs = @{ Key = $Key; ContentType = $ContentType; KeyId = $KeyId; HasKey = $null -ne $EncryptionKey }
            $Copy = [System.IO.MemoryStream]::new()
            $Stream.CopyTo($Copy)
            $script:Uploaded = $Copy.ToArray()
            [pscustomobject]@{ Key = $Key; Bytes = $script:Uploaded.Length; VersionId = 'v-zip' }
        }
    }

    It 'exports mail as .eml, other items as .json plus .fts, and folders as directories' {
        $Prefix = 'p1/tid/exchange/owner1/'
        $Mime = [System.Text.Encoding]::UTF8.GetBytes("Subject: Hello`r`n`r`nBody")
        Set-Stored -Key "$($Prefix)items/f1/m1.eml" -Bytes $Mime -Encrypt
        Set-Stored -Key "$($Prefix)items/f2/e1.fts" -Bytes ([byte[]](1, 2, 3, 4)) -Encrypt
        $script:Entries.Add((New-Entry -Key 'items/f1/' -Path '' -Name 'Inbox' -Type 'folder'))
        $script:Entries.Add((New-Entry -Key 'items/f1/m1.fts' -Path 'Inbox' -Name 'Hello: <world>?' -Type 'message' -Extra ([pscustomobject]@{ id = 'm1'; from = 'a@contoso.com'; eml = 'items/f1/m1.eml' })))
        $script:Entries.Add((New-Entry -Key 'items/f2/e1.fts' -Path 'Calendar' -Name 'Standup' -Type 'event' -Extra ([pscustomobject]@{ id = 'e1' })))
        $script:Entries.Add((New-Entry -Key 'items/f2/gone.fts' -Path 'Calendar' -Name 'Gone' -Type 'event' -Deleted))

        $Result = Invoke-CIPPCloudBackupExport -Context (New-ExportContext -Encrypted)

        $Result.Key | Should -Be 'p1/exports/job1.zip'
        $Result.Items | Should -Be 2
        $Result.Failed | Should -Be 0
        $script:UploadArgs.ContentType | Should -Be 'application/zip'
        $script:UploadArgs.KeyId | Should -Be $script:KeyId
        $script:UploadArgs.HasKey | Should -BeTrue
        Should -Invoke Get-CIPPCloudBackupKey -Times 0 -Exactly

        $Zip = Read-Zip $script:Uploaded
        $Names = @($Zip.Keys)
        $Names | Should -Contain 'Inbox/'
        $Eml = @($Names.Where({ $_ -like 'Inbox/Hello_ _world__ `[*`].eml' }))
        $Eml.Count | Should -Be 1
        Get-Text $Zip[$Eml[0]] | Should -Be "Subject: Hello`r`n`r`nBody"
        $Json = @($Names.Where({ $_ -like 'Calendar/Standup `[*`].json' }))
        $Json.Count | Should -Be 1
        $Details = Get-Text $Zip[$Json[0]] | ConvertFrom-Json
        $Details.type | Should -Be 'event'
        $Details.name | Should -Be 'Standup'
        $Fts = $Json[0] -replace '\.json$', '.fts'
        $Zip[$Fts] | Should -Be ([byte[]](1, 2, 3, 4))
        $Names | Should -Contain '_export-report.txt'
        Get-Text $Zip['_export-report.txt'] | Should -Match 'No problems'
        Get-Text $Zip['_export-report.txt'] | Should -Match 'Owner: Owner One \(owner1\)'
    }

    It 'picks the .eml version written with the .fts version at that point in time' {
        $Prefix = 'p1/tid/exchange/owner1/'
        Set-Stored -Key "$($Prefix)items/f1/m1.eml" -Bytes ([System.Text.Encoding]::UTF8.GetBytes('old')) -VersionId 'eml-1'
        Set-Stored -Key "$($Prefix)items/f1/m1.eml" -Bytes ([System.Text.Encoding]::UTF8.GetBytes('new')) -VersionId 'eml-2'
        Mock Get-CIPPCloudBackupObjectVersionList {
            $Base = [datetime]::new(2026, 11, 1, 0, 0, 0, [System.DateTimeKind]::Utc)
            [pscustomobject]@{ Key = 'p1/tid/exchange/owner1/items/f1/m1.fts'; VersionId = 'fts-1'; IsDeleteMarker = $false; LastModified = $Base.AddHours(1) }
            [pscustomobject]@{ Key = 'p1/tid/exchange/owner1/items/f1/m1.eml'; VersionId = 'eml-1'; IsDeleteMarker = $false; LastModified = $Base.AddHours(1) }
            [pscustomobject]@{ Key = 'p1/tid/exchange/owner1/items/f1/m1.fts'; VersionId = 'fts-2'; IsDeleteMarker = $false; LastModified = $Base.AddHours(5) }
            [pscustomobject]@{ Key = 'p1/tid/exchange/owner1/items/f1/m1.eml'; VersionId = 'eml-2'; IsDeleteMarker = $false; LastModified = $Base.AddHours(5).AddSeconds(2) }
        }
        $script:Entries.Add((New-Entry -Key 'items/f1/m1.fts' -Path 'Inbox' -Name 'Hi' -Type 'message' -VersionId 'fts-1' -Extra ([pscustomobject]@{ eml = 'items/f1/m1.eml' })))

        $null = Invoke-CIPPCloudBackupExport -Context (New-ExportContext)

        $Zip = Read-Zip $script:Uploaded
        $Eml = @($Zip.Keys).Where({ $_ -like '*.eml' })
        Get-Text $Zip[$Eml[0]] | Should -Be 'old'
        Should -Invoke Get-CIPPCloudBackupObjectVersionList -Times 1 -Exactly -ParameterFilter { $Prefix -eq 'p1/tid/exchange/owner1/items/f1/m1.' }
    }

    It 'falls back to .json and .fts when the .eml is missing' {
        Set-Stored -Key 'p1/tid/exchange/owner1/items/f1/m1.fts' -Bytes ([byte[]](9, 9))
        $script:Entries.Add((New-Entry -Key 'items/f1/m1.fts' -Path 'Inbox' -Name 'Hi' -Type 'message' -Extra ([pscustomobject]@{ eml = 'items/f1/m1.eml'; from = 'x@contoso.com' })))

        $Result = Invoke-CIPPCloudBackupExport -Context (New-ExportContext)

        $Result.Items | Should -Be 1
        $Names = @((Read-Zip $script:Uploaded).Keys)
        @($Names.Where({ $_ -like 'Inbox/Hi `[*`].json' })).Count | Should -Be 1
        @($Names.Where({ $_ -like 'Inbox/Hi `[*`].fts' })).Count | Should -Be 1
        @($Names.Where({ $_ -like '*.eml' })).Count | Should -Be 0
    }

    It 'keeps file paths, makes clashing names unique and reads the version at the point in time' {
        $Prefix = 'p1/tid/onedrive/owner1/'
        Set-Stored -Key "$($Prefix)items/d1/i1" -Bytes ([System.Text.Encoding]::UTF8.GetBytes('one')) -VersionId 'v1'
        Set-Stored -Key "$($Prefix)items/d1/i2" -Bytes ([System.Text.Encoding]::UTF8.GetBytes('two')) -VersionId 'v2'
        Set-Stored -Key "$($Prefix)items/d1/i3" -Bytes ([System.Text.Encoding]::UTF8.GetBytes('three')) -VersionId 'v3'
        $script:Entries.Add((New-Entry -Key 'items/d1/f1' -Path '/' -Name 'Projects' -Type 'folder'))
        $script:Entries.Add((New-Entry -Key 'items/d1/f2' -Path '/Projects' -Name 'Empty' -Type 'folder'))
        $script:Entries.Add((New-Entry -Key 'items/d1/i1' -Path '/Projects' -Name 'plan.docx' -Type 'file' -VersionId 'v1'))
        $script:Entries.Add((New-Entry -Key 'items/d1/i2' -Path '/Projects' -Name 'PLAN.docx' -Type 'file' -VersionId 'v2'))
        $script:Entries.Add((New-Entry -Key 'items/d1/i3' -Path '/../Odd' -Name 'a|b?.txt' -Type 'file' -VersionId 'v3'))

        $Result = Invoke-CIPPCloudBackupExport -Context (New-ExportContext -Workload 'onedrive')

        $Result.Items | Should -Be 3
        $Zip = Read-Zip $script:Uploaded
        Get-Text $Zip['Projects/plan.docx'] | Should -Be 'one'
        Get-Text $Zip['Projects/PLAN (2).docx'] | Should -Be 'two'
        Get-Text $Zip['_/Odd/a_b_.txt'] | Should -Be 'three'
        @($Zip.Keys) | Should -Contain 'Projects/Empty/'
        $script:UploadArgs.KeyId | Should -BeNullOrEmpty
    }

    It 'puts SharePoint files under their library name' {
        Set-Stored -Key 'p1/tid/sharepoint/owner1/items/d1/i1' -Bytes ([byte[]](1))
        $script:Entries.Add((New-Entry -Key 'items/d1/i1' -Path '/General' -Name 'notes.txt' -Type 'file' -Extra ([pscustomobject]@{ driveName = 'Documents' })))

        $null = Invoke-CIPPCloudBackupExport -Context (New-ExportContext -Workload 'sharepoint')

        @((Read-Zip $script:Uploaded).Keys) | Should -Contain 'Documents/General/notes.txt'
    }

    It 'streams a large encrypted file through temporary files without growing it' {
        $Large = [byte[]]::new(20MB + 17)
        [System.Random]::new(5).NextBytes($Large)
        Set-Stored -Key 'p1/tid/onedrive/owner1/items/d1/big' -Bytes $Large -Encrypt
        $script:Entries.Add((New-Entry -Key 'items/d1/big' -Path '/' -Name 'big.bin' -Type 'file'))

        $Result = Invoke-CIPPCloudBackupExport -Context (New-ExportContext -Workload 'onedrive' -Encrypted)

        $script:ReceiveStreams | Should -Be @('FileStream')
        $script:UploadStreamType | Should -Be 'FileStream'
        $Result.Bytes | Should -Be $script:Uploaded.Length
        $script:Uploaded.Length | Should -BeLessThan ($Large.Length * 1.01)
        $Zip = Read-Zip $script:Uploaded
        [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Zip['big.bin'])) | Should -Be ([System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Large)))
    }

    It 'lists failed items in the report and keeps exporting the rest' {
        Set-Stored -Key 'p1/tid/onedrive/owner1/items/d1/ok' -Bytes ([byte[]](1))
        $Damaged = Protect-Bytes ([byte[]](1, 2, 3))
        $Damaged[$Damaged.Length - 1] = $Damaged[$Damaged.Length - 1] -bxor 1
        $script:Store['p1/tid/onedrive/owner1/items/d1/bad|'] = @{ Bytes = $Damaged; ContentType = 'application/octet-stream' }
        $script:Entries.Add((New-Entry -Key 'items/d1/missing' -Path '/' -Name 'missing.txt' -Type 'file'))
        $script:Entries.Add((New-Entry -Key 'items/d1/bad' -Path '/' -Name 'bad.txt' -Type 'file'))
        $script:Entries.Add((New-Entry -Key 'items/d1/ok' -Path '/' -Name 'ok.txt' -Type 'file'))

        $Result = Invoke-CIPPCloudBackupExport -Context (New-ExportContext -Workload 'onedrive')

        $Result.Items | Should -Be 1
        $Result.Failed | Should -Be 2
        $Result.Warnings.Count | Should -Be 2
        $Zip = Read-Zip $script:Uploaded
        @($Zip.Keys) | Should -Be @('ok.txt', '_export-report.txt')
        $Report = Get-Text $Zip['_export-report.txt']
        $Report | Should -Match 'could not be exported: 2'
        $Report | Should -Match '/missing.txt: could not be exported: The stored file was not found'
        $Report | Should -Match '/bad.txt: could not be exported: .*damaged'
    }

    It 'reads the job items in batches until a short batch' {
        for ($i = 0; $i -lt 450; $i++) {
            Set-Stored -Key "p1/tid/onedrive/owner1/items/d1/i$i" -Bytes ([byte[]](1))
            $script:Entries.Add((New-Entry -Key "items/d1/i$i" -Path '/' -Name "f$i.txt" -Type 'file'))
        }

        $Result = Invoke-CIPPCloudBackupExport -Context (New-ExportContext -Workload 'onedrive')

        $Result.Items | Should -Be 450
        Should -Invoke Get-CIPPCloudBackupJobItemBatch -Times 3 -Exactly
        Should -Invoke Get-CIPPCloudBackupJobItemBatch -Times 1 -Exactly -ParameterFilter { $Offset -eq 400 -and $Count -eq 200 }
    }

    It 'rejects an unknown workload' {
        { Invoke-CIPPCloudBackupExport -Context (New-ExportContext -Workload 'yammer') } | Should -Throw -ExceptionType ([System.ArgumentException])
    }
}

Describe 'Invoke-CIPPCloudBackupExport for Teams' {
    BeforeEach {
        $script:Store = @{}
        $script:Entries = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPCloudBackupKey { , ([byte[]]$script:Key.Clone()) }
        Mock Get-CIPPCloudBackupJobItemBatch {
            $Last = [Math]::Min($Offset + $Count, $script:Entries.Count)
            for ($i = $Offset; $i -lt $Last; $i++) { $script:Entries[$i] }
        }
        Mock Receive-CIPPCloudBackupObjectStream {
            $Stored = $script:Store["$Key|$VersionId"]
            if (-not $Stored) { return $null }
            $OutStream.Write($Stored.Bytes, 0, $Stored.Bytes.Length)
            [pscustomobject]@{ Key = $Key; VersionId = $VersionId; Bytes = $Stored.Bytes.Length; ContentType = $Stored.ContentType; Metadata = @{} }
        }
        Mock Send-CIPPCloudBackupObjectStream {
            $Copy = [System.IO.MemoryStream]::new()
            $Stream.CopyTo($Copy)
            $script:Uploaded = $Copy.ToArray()
            [pscustomobject]@{ Key = $Key; Bytes = $script:Uploaded.Length; VersionId = $null }
        }

        $script:AddMessage = {
            param($Chat, $Id, $Body, $Created, $ReplyTo, $From = 'Ada', $Location = '1:1 chat', $Attachments = @(), $Hosted = @())
            $Message = [ordered]@{
                id                 = $Id
                replyToId          = $ReplyTo
                messageType        = 'message'
                createdDateTime    = $Created
                lastEditedDateTime = $null
                chatId             = $Chat
                from               = @{ user = @{ id = 'u1'; displayName = $From } }
                body               = @{ contentType = 'html'; content = $Body }
                attachments        = $Attachments
            }
            $Key = "items/$Chat/$Id.json"
            Set-Stored -Key "p1/tid/teams/owner1/$Key" -Bytes ([System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject $Message -Depth 10))) -Encrypt
            $script:Entries.Add((New-Entry -Key $Key -Path $Location -Name $From -Type 'chatMessage' -Extra ([pscustomobject]@{ chatId = $Chat; hostedContents = $Hosted })))
        }
    }

    It 'renders an escaped transcript per conversation with raw JSON and inline images' {
        $Png = [byte[]](0x89, 0x50, 0x4E, 0x47)
        Set-Stored -Key 'p1/tid/teams/owner1/items/c1/m2/aGVsbG8=' -Bytes $Png -ContentType 'image/png' -Encrypt
        & $script:AddMessage -Chat 'c1' -Id 'm2' -Created '2026-11-01T10:05:00Z' -From 'Bob <b>bold</b>' `
            -Body '<p>&lt;script&gt;alert(1)&lt;/script&gt;</p><img src="x" onerror="alert(2)"><p>a &amp; b</p>' `
            -Attachments @(@{ name = 'evil'; contentUrl = 'javascript:alert(3)' }, @{ name = 'Spec "v2".docx'; contentUrl = 'https://contoso.sharepoint.com/spec.docx?a=1&b=2' }) `
            -Hosted @('items/c1/m2/aGVsbG8=')
        & $script:AddMessage -Chat 'c1' -Id 'm1' -Created '2026-11-01T10:00:00Z' -Body 'first'
        & $script:AddMessage -Chat 'c1' -Id 'm3' -Created '2026-11-01T10:01:00Z' -ReplyTo 'm1' -Body 'reply to first'
        & $script:AddMessage -Chat 'c2' -Id 'm9' -Created '2026-11-01T09:00:00Z' -Body 'other chat'

        $Result = Invoke-CIPPCloudBackupExport -Context (New-ExportContext -Workload 'teams' -Encrypted)

        $Result.Items | Should -Be 4
        $Result.Failed | Should -Be 0
        $Zip = Read-Zip $script:Uploaded
        $Names = @($Zip.Keys)
        $Names | Should -Contain '1_1 chat/transcript.html'
        $Names | Should -Contain '1_1 chat (2)/transcript.html'
        $Names | Should -Contain '1_1 chat/messages/m1.json'
        $Names | Should -Contain '1_1 chat (2)/messages/m9.json'
        $Zip['1_1 chat/hosted/m2-1.png'] | Should -Be $Png
        (Get-Text $Zip['1_1 chat/messages/m2.json'] | ConvertFrom-Json).id | Should -Be 'm2'

        $Html = Get-Text $Zip['1_1 chat/transcript.html']
        $Html | Should -Not -Match '<script'
        $Html | Should -Not -Match 'onerror'
        $Html | Should -Not -Match 'javascript:'
        $Html | Should -Not -Match '<b>'
        $Html | Should -Match '&lt;script&gt;alert\(1\)&lt;/script&gt;'
        $Html | Should -Match 'Bob &lt;b&gt;bold&lt;/b&gt;'
        $Html | Should -Match 'a &amp; b'
        $Html | Should -Match '<img src="hosted/m2-1.png" alt="Image">'
        $Html | Should -Match '<a href="https://contoso.sharepoint.com/spec.docx\?a=1&amp;b=2" rel="noopener noreferrer">Spec &quot;v2&quot;.docx</a>'
        $Html | Should -Match '<li>evil</li>'
        $Html | Should -Match "default-src 'none'"
        $First = $Html.IndexOf('first')
        $Reply = $Html.IndexOf('reply to first')
        $Later = $Html.IndexOf('alert(1)')
        $First | Should -BeLessThan $Reply
        $Reply | Should -BeLessThan $Later
        $Html | Should -Match '<div class="msg reply">'
    }

    It 'still exports a message whose inline image is missing and reports the image' {
        & $script:AddMessage -Chat 'c1' -Id 'm1' -Created '2026-11-01T10:00:00Z' -Body 'hi' -Hosted @('items/c1/m1/missing')

        $Result = Invoke-CIPPCloudBackupExport -Context (New-ExportContext -Workload 'teams')

        $Result.Items | Should -Be 1
        $Result.Failed | Should -Be 0
        $Result.Warnings[0] | Should -Match 'inline image of message m1'
        Get-Text (Read-Zip $script:Uploaded)['_export-report.txt'] | Should -Match 'Problems:'
    }
}

Describe 'Invoke-CIPPCloudBackupExport upload encryption' {
    BeforeEach {
        $script:Store = @{}
        $script:Entries = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPCloudBackupKey { , ([byte[]]$script:Key.Clone()) }
        Mock Get-CIPPCloudBackupJobItemBatch {
            $Last = [Math]::Min($Offset + $Count, $script:Entries.Count)
            for ($i = $Offset; $i -lt $Last; $i++) { $script:Entries[$i] }
        }
        Mock Receive-CIPPCloudBackupObjectStream {
            $Stored = $script:Store["$Key|$VersionId"]
            if (-not $Stored) { return $null }
            $OutStream.Write($Stored.Bytes, 0, $Stored.Bytes.Length)
            [pscustomobject]@{ Key = $Key; VersionId = $VersionId; Bytes = $Stored.Bytes.Length; ContentType = $Stored.ContentType; Metadata = @{} }
        }
        Mock Set-CIPPCloudBackupObject {
            $script:Stored = $Body
            [pscustomobject]@{ Key = $Key; Bytes = $Body.Length; VersionId = 'v1' }
        }
        Mock Send-CIPPCloudBackupAzureObjectStream {
            $Copy = [System.IO.MemoryStream]::new()
            $Copy.Write($FirstBlock, 0, $FirstBlock.Length)
            do {
                $Block = Read-CIPPCloudBackupStreamBlock -Reader $Reader -Size 8MB
                $Copy.Write($Block, 0, $Block.Length)
            } while ($Block.Length -eq 8MB)
            $script:Stored = $Copy.ToArray()
            [pscustomobject]@{ Key = $Key; Bytes = $Copy.Length; VersionId = 'v1' }
        }
    }

    It 'stores a <Label> zip encrypted with the policy key that decrypts to the export' -ForEach @(
        @{ Label = 'small'; Size = 1000 }
        @{ Label = 'multi-block'; Size = 20MB + 17 }
    ) {
        $Data = [byte[]]::new($Size)
        [System.Random]::new(5).NextBytes($Data)
        Set-Stored -Key 'p1/tid/onedrive/owner1/items/d1/f' -Bytes $Data -Encrypt
        $script:Entries.Add((New-Entry -Key 'items/d1/f' -Path '/' -Name 'data.bin' -Type 'file'))

        $Result = Invoke-CIPPCloudBackupExport -Context (New-ExportContext -Workload 'onedrive' -Encrypted)

        $Result.Bytes | Should -Be $script:Stored.Length
        [System.Text.Encoding]::ASCII.GetString($script:Stored, 0, 8) | Should -Be 'CIPPENC2'
        $Plain = [System.IO.MemoryStream]::new()
        $null = Unprotect-CIPPCloudBackupStream -InputStream ([System.IO.MemoryStream]::new($script:Stored)) -OutputStream $Plain
        $Zip = Read-Zip $Plain.ToArray()
        [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Zip['data.bin'])) | Should -Be ([System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Data)))
    }
}

Describe 'Unprotect-CIPPCloudBackupStream key cache' {
    It 'reads the key once and reuses it for later objects' {
        Mock Get-CIPPCloudBackupKey { , ([byte[]]$script:Key.Clone()) }
        $Cache = @{}
        foreach ($i in 1..3) {
            $Out = [System.IO.MemoryStream]::new()
            $null = Unprotect-CIPPCloudBackupStream -InputStream ([System.IO.MemoryStream]::new((Protect-Bytes ([byte[]](1, 2, $i))))) -OutputStream $Out -KeyCache $Cache
            $Out.ToArray() | Should -Be ([byte[]](1, 2, $i))
        }
        Should -Invoke Get-CIPPCloudBackupKey -Times 1 -Exactly
        $Cache[$script:KeyId] | Should -Be $script:Key
    }
}
