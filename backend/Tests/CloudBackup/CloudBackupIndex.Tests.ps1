BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    if (-not ('CIPP.CippJson' -as [type])) { Add-Type -Path (Join-Path $BackendRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') }
    $CloudBackup = Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup'
    foreach ($Name in 'Get-CIPPCloudBackupIndexFile', 'Get-CIPPCloudBackupRecoveryPoint', 'Open-CIPPCloudBackupIndexReader',
        'Read-CIPPCloudBackupIndexState', 'Get-CIPPCloudBackupOwnerListing', 'Invoke-CIPPCloudBackupIndexCompaction',
        'Remove-CIPPCloudBackupIndexHistory', 'Read-CIPPCloudBackupStreamBlock', 'Protect-CIPPCloudBackupStream',
        'Unprotect-CIPPCloudBackupStream', 'Unprotect-CIPPCloudBackupStreamBlock', 'Protect-CIPPCloudBackupData', 'Unprotect-CIPPCloudBackupData') {
        . (Join-Path $CloudBackup "$Name.ps1")
    }

    function Get-CIPPCloudBackupKey { param($KeyId) }
    function Get-CIPPCloudBackupObjectList { param($Destination, $Prefix) }
    function Receive-CIPPCloudBackupObjectStream { param($Destination, $Key, $VersionId, [System.IO.Stream]$OutStream) }
    function Send-CIPPCloudBackupObjectStream { param($Destination, $Key, [System.IO.Stream]$Stream, $ContentType, $Metadata, $KeyId, [byte[]]$EncryptionKey) }
    function Remove-CIPPCloudBackupObject {
        [CmdletBinding(SupportsShouldProcess = $true)]
        param($Destination, $Key, $VersionId)
    }

    $script:Destination = [pscustomobject]@{ Provider = 'AzureBlob' }
    $script:KeyId = '0f8fad5b-d9cb-469f-a165-70867728950e'
    $script:TestKey = [byte[]](1..32)

    function Get-TestBody {
        param([object[]]$Entries, [switch]$Encrypt)
        $Buffer = [System.IO.MemoryStream]::new()
        $Gzip = [System.IO.Compression.GZipStream]::new($Buffer, [System.IO.Compression.CompressionLevel]::Optimal, $true)
        $Writer = [System.IO.StreamWriter]::new($Gzip, [System.Text.UTF8Encoding]::new($false))
        foreach ($Entry in $Entries) { $Writer.Write((ConvertTo-Json -InputObject $Entry -Depth 10 -Compress)); $Writer.Write("`n") }
        $Writer.Dispose()
        $Bytes = $Buffer.ToArray()
        if (-not $Encrypt) { return , $Bytes }
        $Out = [System.IO.MemoryStream]::new()
        $null = Protect-CIPPCloudBackupStream -InputStream ([System.IO.MemoryStream]::new($Bytes)) -OutputStream $Out -KeyId $script:KeyId -Key $script:TestKey -ChunkSize 64
        , $Out.ToArray()
    }

    function Add-TestPart {
        param([string]$Stamp, [int]$Part = 0, [object[]]$Entries, [switch]$Encrypt, [string]$Prefix = $script:Prefix)
        $Name = '{0}index/{1}-{2:D5}.jsonl.gz' -f $Prefix, $Stamp, $Part
        if ($Encrypt) { $Name = "$Name.enc" }
        $script:Store[$Name] = Get-TestBody -Entries $Entries -Encrypt:$Encrypt
    }

    function New-TestEntry {
        param($k, $p, $n, $t = 'message', $s = 10, $m = '2026-01-01T00:00:00Z', $v = 'v1', [bool]$d = $false, $x = $null)
        [ordered]@{ k = $k; p = $p; n = $n; t = $t; s = $s; m = $m; v = $v; d = $d; x = $x }
    }

    function ConvertTo-TestText {
        param($Listing)
        $Rows = foreach ($Item in @($Listing.Items) + @($Listing.Folders)) {
            [ordered]@{
                Key = $Item.Key; Path = $Item.Path; Name = $Item.Name; Type = $Item.Type; Size = $Item.Size
                Modified = if ($Item.Modified) { $Item.Modified.ToString('o') } else { $null }
                VersionId = $Item.VersionId; Deleted = $Item.Deleted; RunStamp = $Item.RunStamp
                Extra = if ($null -eq $Item.Extra) { $null } else { ConvertTo-Json -InputObject $Item.Extra -Depth 5 -Compress }
            }
        }
        "$($Listing.RunStamp)|$($Listing.Total)|$(ConvertTo-Json -InputObject @($Rows) -Depth 5 -Compress)"
    }
}

Describe 'Cloud backup index' {
    BeforeEach {
        $script:Store = [System.Collections.Generic.SortedDictionary[string, byte[]]]::new([System.StringComparer]::Ordinal)
        $script:Prefix = 'pol/tid/exchange/u1/'
        Mock Get-CIPPCloudBackupKey { , ([byte[]]$script:TestKey.Clone()) }
        Mock Get-CIPPCloudBackupObjectList {
            foreach ($Name in @($script:Store.Keys)) {
                if ($Name.StartsWith($Prefix)) { [pscustomobject]@{ Key = $Name; Size = $script:Store[$Name].Length; LastModified = [datetime]::UtcNow } }
            }
        }
        Mock Receive-CIPPCloudBackupObjectStream {
            if (-not $script:Store.ContainsKey($Key)) { return $null }
            $Body = $script:Store[$Key]
            $OutStream.Write($Body, 0, $Body.Length)
            [pscustomobject]@{ Key = $Key; VersionId = $null; Bytes = $Body.Length }
        }
        Mock Send-CIPPCloudBackupObjectStream {
            $Out = [System.IO.MemoryStream]::new()
            if ($KeyId) {
                $null = Protect-CIPPCloudBackupStream -InputStream $Stream -OutputStream $Out -KeyId $KeyId -Key $EncryptionKey
            } else {
                $Stream.CopyTo($Out)
            }
            $script:Store[$Key] = $Out.ToArray()
            [pscustomobject]@{ Key = $Key; Bytes = $Out.Length; VersionId = $null }
        }
        Mock Remove-CIPPCloudBackupObject { $null = $script:Store.Remove($Key) }
    }

    Describe 'Get-CIPPCloudBackupRecoveryPoint' {
        It 'lists each run once, newest first, from parts and snapshots' {
            Add-TestPart -Stamp '20260101T000000Z' -Entries @(New-TestEntry 'items/f/a.fts' 'Inbox' 'A')
            Add-TestPart -Stamp '20260101T000000Z' -Part 1 -Entries @(New-TestEntry 'items/f/b.fts' 'Inbox' 'B')
            Add-TestPart -Stamp '20260102T000000Z' -Entries @(New-TestEntry 'items/f/c.fts' 'Inbox' 'C')
            $script:Store["$($script:Prefix)index/snapshot-20260102T000000Z.jsonl.gz.enc"] = Get-TestBody -Entries @() -Encrypt
            $script:Store["$($script:Prefix)index/notes.txt"] = [byte[]]@(1)

            $Points = @(Get-CIPPCloudBackupRecoveryPoint -Destination $script:Destination -OwnerPrefix $script:Prefix)

            $Points.RunStamp | Should -Be @('20260102T000000Z', '20260101T000000Z')
            $Points[0].At | Should -Be ([datetime]::new(2026, 1, 2, 0, 0, 0, [System.DateTimeKind]::Utc))
            $Points[0].At.Kind | Should -Be 'Utc'
        }
    }

    Describe 'Get-CIPPCloudBackupOwnerListing' {
        Context 'replay' {
            BeforeEach {
                Add-TestPart -Stamp '20260101T000000Z' -Entries @(
                    New-TestEntry 'items/F1/' '' 'Inbox' -t 'folder' -s $null -m $null -v $null -x @{ id = 'F1'; parentId = 'ROOT'; type = 'IPF.Note' }
                    New-TestEntry 'items/F1/a.fts' 'Inbox' 'Hello' -v 'a1' -m '2026-01-01T10:00:00Z' -x @{ from = 'ann@contoso.com'; to = 'bob@contoso.com'; eml = 'items/F1/a.eml' }
                    New-TestEntry 'items/F1/b.fts' 'Inbox' 'Budget' -v 'b1' -m '2026-01-01T11:00:00Z' -x @{ from = 'cy@contoso.com'; to = 'ann@contoso.com' }
                )
                Add-TestPart -Stamp '20260102T000000Z' -Entries @(
                    New-TestEntry 'items/F1/a.fts' 'Inbox' 'Hello again' -v 'a2' -m '2026-01-02T10:00:00Z' -x @{ from = 'ann@contoso.com' }
                    New-TestEntry 'items/F1/b.fts' 'Inbox' $null -s $null -m $null -v $null -d $true -x @{ id = 'b' }
                    New-TestEntry 'items/F1/c.fts' 'Inbox' 'Contract' -v 'c1' -m '2026-01-02T09:00:00Z' -x @{ from = 'legal@fabrikam.com' }
                )
                Add-TestPart -Stamp '20260103T000000Z' -Entries @(
                    New-TestEntry 'items/F1/b.fts' 'Inbox' 'Budget v2' -v 'b3' -m '2026-01-03T09:00:00Z' -x @{ from = 'cy@contoso.com' }
                )
            }

            It 'applies edits, deletes and re-adds in order with the last write winning' {
                $Day1 = Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf '20260101T000000Z'
                $Day1.RunStamp | Should -Be '20260101T000000Z'
                $Day1.Items.Name | Should -Be @('Budget', 'Hello')
                $Day1.Items[1].Extra.eml | Should -Be 'items/F1/a.eml'

                $Day2 = Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf '20260102T000000Z'
                $Day2.Total | Should -Be 2
                $Day2.Items.Name | Should -Be @('Hello again', 'Contract')
                $Day2.Items[0].VersionId | Should -Be 'a2'
                $Day2.Items[0].RunStamp | Should -Be '20260102T000000Z'
                $Day2.Items[0].Path | Should -Be 'Inbox'

                $Day3 = Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix
                $Day3.RunStamp | Should -Be '20260103T000000Z'
                $Day3.Items.Name | Should -Be @('Budget v2', 'Hello again', 'Contract')
            }

            It 'keeps the last live name and version of a deleted item when deleted items are included' {
                $Day2 = Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf '20260102T000000Z' -IncludeDeleted
                $Deleted = @($Day2.Items | Where-Object Deleted)
                $Deleted.Count | Should -Be 1
                $Deleted[0].Key | Should -Be 'items/F1/b.fts'
                $Deleted[0].Name | Should -Be 'Budget'
                $Deleted[0].VersionId | Should -Be 'b1'
                $Deleted[0].RunStamp | Should -Be '20260102T000000Z'
                $Deleted[0].Extra.from | Should -Be 'cy@contoso.com'
            }

            It 'resolves a datetime to the newest run at or before it and returns nothing before the first run' {
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf ([datetime]::new(2026, 1, 2, 23, 59, 59, [System.DateTimeKind]::Utc))).RunStamp | Should -Be '20260102T000000Z'
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf '2026-01-02T00:00:00Z').RunStamp | Should -Be '20260102T000000Z'
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf '2026-01-01T23:59:59Z').RunStamp | Should -Be '20260101T000000Z'
                $Before = Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf '2025-12-31T23:59:59Z'
                $Before.RunStamp | Should -BeNullOrEmpty
                $Before.Total | Should -Be 0
                @($Before.Items).Count | Should -Be 0
            }

            It 'refuses a point in time it cannot read' {
                { Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf 'yesterday-ish' } | Should -Throw -ExceptionType ([System.ArgumentException])
            }

            It 'searches name, sender and recipients case-insensitively' {
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Search 'FABRIKAM').Items.Name | Should -Be @('Contract')
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Search 'budget').Items.Name | Should -Be @('Budget v2')
                @((Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf '20260101T000000Z' -Search 'bob@').Items).Name | Should -Be @('Hello')
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Search 'inbox').Total | Should -Be 3
            }

            It 'filters by modified date and pages newest first' {
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -ModifiedFrom '2026-01-02T09:30:00Z').Items.Name | Should -Be @('Budget v2', 'Hello again')
                $Page = Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Skip 1 -Take 1
                $Page.Total | Should -Be 3
                @($Page.Items).Name | Should -Be @('Hello again')
                @((Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Skip 5).Items).Count | Should -Be 0
            }

            It 'filters by exact key and streams entries with their extra data' {
                $Entries = @(Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Key 'items/F1/a.fts', 'items/F1/c.fts' -Stream)
                ($Entries.Key | Sort-Object) | Should -Be @('items/F1/a.fts', 'items/F1/c.fts')
                ($Entries | Where-Object Key -EQ 'items/F1/c.fts').Extra.from | Should -Be 'legal@fabrikam.com'
                $Entries[0].PSObject.Properties.Name | Should -Be @('Key', 'Path', 'Name', 'Type', 'Size', 'Modified', 'VersionId', 'Deleted', 'Extra', 'RunStamp')
            }
        }

        Context 'folders' {
            It 'follows renamed and moved mail folders for the items inside them' {
                Add-TestPart -Stamp '20260101T000000Z' -Entries @(
                    New-TestEntry 'items/F1/' '' 'Inbox' -t 'folder' -x @{ id = 'F1'; parentId = 'ROOT' }
                    New-TestEntry 'items/F2/' 'Inbox' 'Projects' -t 'folder' -x @{ id = 'F2'; parentId = 'F1' }
                    New-TestEntry 'items/F3/' '' 'Archive' -t 'folder' -x @{ id = 'F3'; parentId = 'ROOT' }
                    New-TestEntry 'items/F2/m.fts' 'Inbox/Projects' 'Plan' -x @{ from = 'a@b.c' }
                )
                Add-TestPart -Stamp '20260102T000000Z' -Entries @(
                    New-TestEntry 'items/F2/' 'Archive' 'Old projects' -t 'folder' -x @{ id = 'F2'; parentId = 'F3' }
                )

                $Day1 = Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf '20260101T000000Z'
                $Day1.Items[0].Path | Should -Be 'Inbox/Projects'
                $Day1.Folders.Path | Should -Be @('Archive', 'Inbox')

                $Day2 = Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix
                $Day2.Items[0].Path | Should -Be 'Archive/Old projects'
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Path 'archive').Folders.Path | Should -Be @('Archive/Old projects')
                @((Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Path 'Inbox').Folders).Count | Should -Be 0
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Path 'Archive/Old projects').Items.Name | Should -Be @('Plan')
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Search 'old proj').Items.Name | Should -Be @('Plan')
            }

            It 'builds drive paths from parent folders, lists direct children or the whole subtree, and filters by type' {
                $script:Prefix = 'pol/tid/onedrive/u1/'
                Add-TestPart -Stamp '20260101T000000Z' -Entries @(
                    New-TestEntry 'items/D/A' '/' 'Docs' -t 'folder' -x @{ driveId = 'D'; driveName = 'OneDrive'; parentId = 'ROOT' }
                    New-TestEntry 'items/D/B' '/Docs' 'Sub' -t 'folder' -x @{ driveId = 'D'; driveName = 'OneDrive'; parentId = 'A' }
                    New-TestEntry 'items/D/1' '/Docs' 'a.docx' -t 'file' -x @{ driveId = 'D'; driveName = 'OneDrive'; parentId = 'A' }
                    New-TestEntry 'items/D/2' '/Docs/Sub' 'b.xlsx' -t 'file' -m '2026-01-02T00:00:00Z' -x @{ driveId = 'D'; driveName = 'OneDrive'; parentId = 'B' }
                    New-TestEntry 'items/D/3' '/' 'root.txt' -t 'file' -x @{ driveId = 'D'; driveName = 'OneDrive'; parentId = 'ROOT' }
                )

                $Root = Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Path '/'
                $Root.Items.Name | Should -Be @('root.txt')
                $Root.Folders.Name | Should -Be @('Docs')
                $Root.Folders[0].Key | Should -Be 'items/D/A'

                $Docs = Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Path 'Docs'
                $Docs.Items.Name | Should -Be @('a.docx')
                $Docs.Folders.Path | Should -Be @('Docs/Sub')

                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Path 'Docs' -Recurse).Items.Name | Should -Be @('b.xlsx', 'a.docx')
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix).Total | Should -Be 3
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Path 'Docs' -Recurse -IncludeFolders).Items.Name | Should -Contain 'Sub'
                @((Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Type 'message').Items).Count | Should -Be 0
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Type 'FILE').Total | Should -Be 3

                Add-TestPart -Stamp '20260102T000000Z' -Entries @(
                    New-TestEntry 'items/D/A' '/' 'Documents' -t 'folder' -x @{ driveId = 'D'; driveName = 'OneDrive'; parentId = 'ROOT' }
                )
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Key 'items/D/2').Items[0].Path | Should -Be 'Documents/Sub'
            }

            It 'puts each SharePoint library at the top of the tree' {
                $script:Prefix = 'pol/tid/sharepoint/site1/'
                Add-TestPart -Stamp '20260101T000000Z' -Entries @(
                    New-TestEntry 'items/D1/1' '/' 'a.txt' -t 'file' -x @{ driveId = 'D1'; driveName = 'Documents'; parentId = 'R1' }
                    New-TestEntry 'items/D2/1' '/' 'b.txt' -t 'file' -x @{ driveId = 'D2'; driveName = 'Policies'; parentId = 'R2' }
                )
                $Root = Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Path ''
                @($Root.Items).Count | Should -Be 0
                $Root.Folders.Path | Should -Be @('Documents', 'Policies')
                $Root.Folders[0].Key | Should -BeNullOrEmpty
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Path 'Policies').Items.Name | Should -Be @('b.txt')
            }

            It 'derives team and channel folders from message locations' {
                $script:Prefix = 'pol/tid/teams/g1/'
                Add-TestPart -Stamp '20260101T000000Z' -Entries @(
                    New-TestEntry 'items/c1/m1.json' 'Board/General' 'Ann: hi' -t 'channelMessage' -x @{ from = 'Ann' }
                    New-TestEntry 'items/c2/m2.json' 'Board/Finance' 'Bob: numbers' -t 'channelMessage' -x @{ from = 'Bob' }
                )
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Path '').Folders.Path | Should -Be @('Board')
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Path 'Board').Folders.Path | Should -Be @('Board/Finance', 'Board/General')
                (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Path 'Board/General').Items.Name | Should -Be @('Ann: hi')
            }
        }

        It 'reads encrypted streaming and whole-object index files' {
            Add-TestPart -Stamp '20260101T000000Z' -Encrypt -Entries @(New-TestEntry 'items/F/a.fts' 'Inbox' 'Secret A' -x @{ from = 'x@y.z' })
            $Plain = Get-TestBody -Entries @(New-TestEntry 'items/F/b.fts' 'Inbox' 'Secret B')
            $script:Store["$($script:Prefix)index/20260101T000000Z-00001.jsonl.gz.enc"] = Protect-CIPPCloudBackupData -Bytes $Plain -KeyId $script:KeyId -Key ([byte[]]$script:TestKey.Clone())

            $Listing = Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix

            ($Listing.Items.Name | Sort-Object) | Should -Be @('Secret A', 'Secret B')
            ($Listing.Items | Where-Object Name -EQ 'Secret A').Extra.from | Should -Be 'x@y.z'
            Should -Invoke Get-CIPPCloudBackupKey -ParameterFilter { "$KeyId" -eq $script:KeyId }
        }

        It 'makes no writes or deletes' {
            Add-TestPart -Stamp '20260101T000000Z' -Entries @(New-TestEntry 'items/F/a.fts' 'Inbox' 'A')
            $null = Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -IncludeDeleted
            Should -Invoke Send-CIPPCloudBackupObjectStream -Times 0 -Exactly
            Should -Invoke Remove-CIPPCloudBackupObject -Times 0 -Exactly
        }
    }

    Describe 'Index compaction and history' {
        BeforeEach {
            $Day = 0
            foreach ($Stamp in '20260101T000000Z', '20260102T000000Z', '20260103T000000Z', '20260104T000000Z', '20260105T000000Z') {
                $Day++
                Add-TestPart -Stamp $Stamp -Entries @(
                    New-TestEntry 'items/F1/' '' 'Inbox' -t 'folder' -x @{ id = 'F1'; parentId = 'ROOT' }
                    New-TestEntry "items/F1/day$Day.fts" 'Inbox' "Day $Day" -v "d$Day" -m ('2026-01-0{0}T08:00:00Z' -f $Day) -x @{ from = "u$Day@contoso.com" }
                    New-TestEntry 'items/F1/edit.fts' 'Inbox' "Edited $Day" -v "e$Day" -m ('2026-01-0{0}T09:00:00Z' -f $Day) -x @{ n = $Day }
                ) -Encrypt
                Add-TestPart -Stamp $Stamp -Part 1 -Entries @(
                    if ($Day -eq 2) { New-TestEntry 'items/F1/day1.fts' 'Inbox' $null -s $null -m $null -v $null -d $true }
                    if ($Day -eq 4) { New-TestEntry 'items/F1/day1.fts' 'Inbox' 'Day 1 back' -v 'd1b' -m '2026-01-04T10:00:00Z' }
                    if ($Day -eq 3) { New-TestEntry 'items/F1/' 'Top' 'Inbox renamed' -t 'folder' -x @{ id = 'F1'; parentId = 'ROOT' } }
                    New-TestEntry "items/F1/late$Day.fts" 'Inbox' "Late $Day" -v "l$Day" -m ('2026-01-0{0}T12:00:00Z' -f $Day)
                ) -Encrypt
            }
            $script:Stamps = @('20260101T000000Z', '20260102T000000Z', '20260103T000000Z', '20260104T000000Z', '20260105T000000Z')
        }

        It 'does not compact before enough parts or enough time' {
            $Result = Invoke-CIPPCloudBackupIndexCompaction -Destination $script:Destination -OwnerPrefix $script:Prefix -KeyId $script:KeyId -Key $script:TestKey -MinParts 50 -MaxAgeDays 100000
            $Result.Compacted | Should -BeFalse
            Should -Invoke Send-CIPPCloudBackupObjectStream -Times 0 -Exactly
        }

        It 'writes an encrypted snapshot that answers every point in time exactly like replaying the parts' {
            $Before = @{}
            foreach ($Stamp in $script:Stamps) {
                $Before[$Stamp] = ConvertTo-TestText (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf $Stamp -IncludeDeleted -IncludeFolders -Take 1000)
            }
            $Later = @(foreach ($Name in @($script:Store.Keys)) { if ($Name -match '2026010[45]') { $Name } })
            $Saved = @{}
            foreach ($Name in $Later) { $Saved[$Name] = $script:Store[$Name]; $null = $script:Store.Remove($Name) }
            $First = Invoke-CIPPCloudBackupIndexCompaction -Destination $script:Destination -OwnerPrefix $script:Prefix -KeyId $script:KeyId -Key $script:TestKey -MinParts 6
            $First.Compacted | Should -BeTrue
            $First.SnapshotStamp | Should -Be '20260103T000000Z'
            $First.PartsMerged | Should -Be 6
            $script:Store.ContainsKey("$($script:Prefix)index/snapshot-20260103T000000Z.jsonl.gz.enc") | Should -BeTrue
            [System.Text.Encoding]::ASCII.GetString($script:Store["$($script:Prefix)index/snapshot-20260103T000000Z.jsonl.gz.enc"], 0, 8) | Should -Be 'CIPPENC2'
            foreach ($Name in $Later) { $script:Store[$Name] = $Saved[$Name] }

            foreach ($Stamp in $script:Stamps) {
                ConvertTo-TestText (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf $Stamp -IncludeDeleted -IncludeFolders -Take 1000) | Should -Be $Before[$Stamp] -Because $Stamp
            }

            $Second = Invoke-CIPPCloudBackupIndexCompaction -Destination $script:Destination -OwnerPrefix $script:Prefix -KeyId $script:KeyId -Key $script:TestKey -MinParts 4
            $Second.SnapshotStamp | Should -Be '20260105T000000Z'
            $Second.PartsMerged | Should -Be 4
            foreach ($Stamp in $script:Stamps) {
                ConvertTo-TestText (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf $Stamp -IncludeDeleted -IncludeFolders -Take 1000) | Should -Be $Before[$Stamp] -Because $Stamp
            }
            (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Key 'items/F1/day3.fts').Items[0].Path | Should -Be 'Inbox'
        }

        It 'compacts when the oldest unmerged change is older than the age limit and keeps parts written to the same run later' {
            $Result = Invoke-CIPPCloudBackupIndexCompaction -Destination $script:Destination -OwnerPrefix $script:Prefix -MinParts 1000 -MaxAgeDays 1
            $Result.Compacted | Should -BeTrue
            $script:Store.ContainsKey("$($script:Prefix)index/snapshot-20260105T000000Z.jsonl.gz") | Should -BeTrue

            Add-TestPart -Stamp '20260105T000000Z' -Part 2 -Entries @(New-TestEntry 'items/F1/edit.fts' 'Inbox' 'Edited after snapshot' -v 'e5b')
            (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -Key 'items/F1/edit.fts').Items[0].Name | Should -Be 'Edited after snapshot'
            (Invoke-CIPPCloudBackupIndexCompaction -Destination $script:Destination -OwnerPrefix $script:Prefix -MinParts 1 -MaxAgeDays 1).Compacted | Should -BeFalse
        }

        It 'drops entries deleted before the cut-off from the snapshot only' {
            Add-TestPart -Stamp '20260105T000000Z' -Part 2 -Entries @(New-TestEntry 'items/F1/late5.fts' 'Inbox' $null -d $true)
            Add-TestPart -Stamp '20260102T000000Z' -Part 2 -Entries @(New-TestEntry 'items/F1/late1.fts' 'Inbox' $null -d $true)
            $null = Invoke-CIPPCloudBackupIndexCompaction -Destination $script:Destination -OwnerPrefix $script:Prefix -MinParts 1 -DeletedBefore '2026-01-03T00:00:00Z'
            $Reader = Open-CIPPCloudBackupIndexReader -Destination $script:Destination -Key "$($script:Prefix)index/snapshot-20260105T000000Z.jsonl.gz"
            try { $Lines = @(while ($null -ne ($L = $Reader.ReadLine())) { [CIPP.CippJson]::ConvertFromJson($L) }) } finally { $Reader.Dispose() }
            ($Lines | Where-Object k -EQ 'items/F1/late5.fts').d | Should -BeTrue
            ($Lines | Where-Object k -EQ 'items/F1/late5.fts').r | Should -Be '20260105T000000Z'
            ($Lines | Where-Object k -EQ 'items/F1/late5.fts').v | Should -Be 'l5'
            ($Lines | Where-Object k -EQ 'items/F1/day1.fts').n | Should -Be 'Day 1 back'
            @($Lines | Where-Object k -EQ 'items/F1/late1.fts').Count | Should -Be 0
            @($Lines).Count | Should -Be 11
        }

        It 'prunes history so every point in time from the cut-off on answers as before' {
            $Before = @{}
            foreach ($Stamp in $script:Stamps) {
                $Before[$Stamp] = ConvertTo-TestText (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf $Stamp -IncludeDeleted -IncludeFolders -Take 1000)
            }
            $Later = @(foreach ($Name in @($script:Store.Keys)) { if ($Name -match '2026010[45]') { $Name } })
            $Saved = @{}
            foreach ($Name in $Later) { $Saved[$Name] = $script:Store[$Name]; $null = $script:Store.Remove($Name) }
            $null = Invoke-CIPPCloudBackupIndexCompaction -Destination $script:Destination -OwnerPrefix $script:Prefix -MinParts 1
            foreach ($Name in $Later) { $script:Store[$Name] = $Saved[$Name] }

            $None = Remove-CIPPCloudBackupIndexHistory -Destination $script:Destination -OwnerPrefix $script:Prefix -OlderThan '2026-01-02T12:00:00Z'
            $None.Removed | Should -Be 0
            $None.SnapshotStamp | Should -BeNullOrEmpty

            $Result = Remove-CIPPCloudBackupIndexHistory -Destination $script:Destination -OwnerPrefix $script:Prefix -OlderThan '2026-01-04T12:00:00Z'
            $Result.SnapshotStamp | Should -Be '20260103T000000Z'
            $Result.Removed | Should -Be 4
            @($script:Store.Keys | Where-Object { $_ -match '2026010[12]T' }).Count | Should -Be 0
            $script:Store.ContainsKey("$($script:Prefix)index/20260103T000000Z-00000.jsonl.gz.enc") | Should -BeTrue

            (Get-CIPPCloudBackupRecoveryPoint -Destination $script:Destination -OwnerPrefix $script:Prefix).RunStamp | Should -Be @('20260105T000000Z', '20260104T000000Z', '20260103T000000Z')
            foreach ($Stamp in '20260103T000000Z', '20260104T000000Z', '20260105T000000Z') {
                ConvertTo-TestText (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf $Stamp -IncludeDeleted -IncludeFolders -Take 1000) | Should -Be $Before[$Stamp] -Because $Stamp
            }
            (Get-CIPPCloudBackupOwnerListing -Destination $script:Destination -OwnerPrefix $script:Prefix -AsOf '2026-01-04T12:00:00Z' -IncludeDeleted -IncludeFolders -Take 1000).RunStamp | Should -Be '20260104T000000Z'
        }
    }
}
