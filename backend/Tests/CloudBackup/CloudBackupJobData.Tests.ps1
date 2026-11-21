BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup'
    if (-not ('CIPP.CippJson' -as [type])) { Add-Type -Path (Join-Path $BackendRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') }

    function Get-CIPPCloudBackupKey { param($KeyId) }
    function Get-CIPPCloudBackupOwnerListing { param($Destination, $OwnerPrefix, $AsOf, $Path, [string[]]$Key, $Search, $Type, [switch]$IncludeDeleted, [switch]$IncludeFolders, [switch]$Recurse, [switch]$Stream, $Skip, $Take) }
    function Get-CIPPCloudBackupPolicy { param($Id) }
    function Get-CIPPCloudBackupDestination { param($Id, [switch]$IncludeSecret) }
    function Get-CIPPTenantLookup { param($Tenants) }
    foreach ($Name in 'Read-CIPPCloudBackupStreamBlock', 'Protect-CIPPCloudBackupStream', 'Unprotect-CIPPCloudBackupStream', 'Unprotect-CIPPCloudBackupStreamBlock', 'Protect-CIPPCloudBackupData', 'Unprotect-CIPPCloudBackupData',
        'Send-CIPPCloudBackupObjectStream', 'Set-CIPPCloudBackupObject', 'Receive-CIPPCloudBackupObjectStream', 'Set-CIPPCloudBackupJsonl', 'Get-CIPPCloudBackupJsonl',
        'Save-CIPPCloudBackupJobManifest', 'Get-CIPPCloudBackupJobItemBatch', 'Read-CIPPCloudBackupObjectPart', 'Get-CIPPCloudBackupJobContext') {
        . (Join-Path $Folder "$Name.ps1")
    }

    $script:KeyId = [guid]::NewGuid().ToString()
    $script:Key = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $script:Destination = [pscustomobject]@{ Provider = 'AzureBlob'; StorageAccount = 'cippbackup'; Container = 'backups' }

    function New-Plain {
        param([int]$Length)
        $Bytes = [byte[]]::new($Length)
        for ($i = 0; $i -lt $Length; $i++) { $Bytes[$i] = [byte](($i * 31 + 7) % 251) }
        , $Bytes
    }
    function New-Entry {
        param([int]$Index, $Path = 'Inbox', $Type = 'message')
        [pscustomobject]@{ Key = "items/f/$Index.fts"; Path = $Path; Name = "Item $Index"; Type = $Type; Size = 10; Modified = '2026-11-01T00:00:00Z'; VersionId = "v$Index"; Deleted = $false; Extra = [pscustomobject]@{ id = "id$Index" }; RunStamp = '20261101T000000Z' }
    }
    function New-Context {
        param([switch]$Encrypted, $JobId = 'job-1', $ManifestJobId)
        [pscustomobject]@{
            JobId         = $JobId
            PolicyId      = 'p1'
            Destination   = $script:Destination
            OwnerPrefix   = 'p1/c1/exchange/u1/'
            RunStamp      = '20261101T000000Z'
            KeyId         = if ($Encrypted) { $script:KeyId } else { $null }
            Key           = if ($Encrypted) { [byte[]]$script:Key.Clone() } else { $null }
            ManifestJobId = $ManifestJobId ?? $JobId
        }
    }
    function Read-Parts {
        param([string]$Key, [int]$PartSize)
        $First = Read-CIPPCloudBackupObjectPart -Destination $script:Destination -Key $Key -PartSize $PartSize
        $All = [System.IO.MemoryStream]::new()
        $All.Write($First.Body, 0, $First.Body.Length)
        for ($Part = 1; $Part -lt $First.Parts; $Part++) {
            $Next = Read-CIPPCloudBackupObjectPart -Destination $script:Destination -Key $Key -Part $Part -PartSize $PartSize
            $All.Write($Next.Body, 0, $Next.Body.Length)
        }
        [pscustomobject]@{ Parts = $First.Parts; Size = $First.Size; Bytes = $All.ToArray() }
    }
}

Describe 'Cloud backup job data' {
    BeforeEach {
        $script:Store = @{}
        $script:BytesRead = [int64]0
        $script:ManifestPartReads = 0
        $script:CIPPCloudBackupManifestPart = $null
        Mock Get-CIPPCloudBackupKey { , [byte[]]$script:Key.Clone() }
        Mock Set-CIPPCloudBackupObject {
            $script:Store[$Key] = @{ Bytes = [byte[]]$Body.Clone(); ContentType = $ContentType }
            [pscustomobject]@{ Key = $Key; Bytes = [int64]$Body.Length; VersionId = 'v1' }
        }
        Mock Receive-CIPPCloudBackupObjectStream {
            $Object = $script:Store[$Key]
            if (-not $Object) { return $null }
            if ($Key -like '*/items/*') { $script:ManifestPartReads++ }
            $Stop = if ($Length -gt 0) { [Math]::Min($Object.Bytes.Length, $Offset + $Length) } else { $Object.Bytes.Length }
            if ($Stop -gt $Offset) {
                $OutStream.Write($Object.Bytes, $Offset, $Stop - $Offset)
                $script:BytesRead += $Stop - $Offset
            }
            [pscustomobject]@{ Key = $Key; VersionId = 'v1'; Bytes = [int64]$Object.Bytes.Length; ContentType = $Object.ContentType }
        }
    }

    Context 'JSON lines objects' {
        It 'round-trips plain and encrypted objects and returns null for a missing one' {
            $Items = @([pscustomobject]@{ A = 1; B = 'x' }, [pscustomobject]@{ A = 2; B = 'y' })
            $null = Set-CIPPCloudBackupJsonl -Destination $script:Destination -Key 'plain' -Items $Items
            $null = Set-CIPPCloudBackupJsonl -Destination $script:Destination -Key 'enc' -Items $Items -KeyId $script:KeyId -EncryptionKey ([byte[]]$script:Key.Clone())

            $script:Store['plain'].Bytes[0] | Should -Be 0x1f
            [System.Text.Encoding]::ASCII.GetString($script:Store['enc'].Bytes, 0, 8) | Should -Be 'CIPPENC2'
            foreach ($Name in 'plain', 'enc') {
                $Read = Get-CIPPCloudBackupJsonl -Destination $script:Destination -Key $Name
                @($Read).Count | Should -Be 2
                $Read[1].B | Should -Be 'y'
            }
            Get-CIPPCloudBackupJsonl -Destination $script:Destination -Key 'missing' | Should -BeNullOrEmpty
        }
    }

    Context 'Job manifest' {
        It 'streams the whole owner into parts of 500 and reads batches across part boundaries' -ForEach @(@{ Encrypted = $false }, @{ Encrypted = $true }) {
            Mock Get-CIPPCloudBackupOwnerListing { foreach ($i in 0..1202) { New-Entry -Index $i } }
            $Context = New-Context -Encrypted:$Encrypted

            $Manifest = Save-CIPPCloudBackupJobManifest -Context $Context

            $Manifest.Items | Should -Be 1203
            $Manifest.Parts | Should -Be 3
            Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 1 -Exactly -ParameterFilter { $Stream -and $Recurse -and $IncludeFolders -and $AsOf -eq '20261101T000000Z' -and -not $PesterBoundParameters.ContainsKey('Path') }
            $Suffix = if ($Encrypted) { '.enc' } else { '' }
            @($script:Store.Keys | Sort-Object) | Should -Be @("p1/jobs/job-1/items/00000.jsonl.gz$Suffix", "p1/jobs/job-1/items/00001.jsonl.gz$Suffix", "p1/jobs/job-1/items/00002.jsonl.gz$Suffix")
            if ($Encrypted) { [System.Text.Encoding]::ASCII.GetString($script:Store["p1/jobs/job-1/items/00000.jsonl.gz.enc"].Bytes, 0, 8) | Should -Be 'CIPPENC2' }

            $Batch = Get-CIPPCloudBackupJobItemBatch -Context $Context -Offset 498 -Count 5
            @($Batch.Key) | Should -Be @('items/f/498.fts', 'items/f/499.fts', 'items/f/500.fts', 'items/f/501.fts', 'items/f/502.fts')
            $Batch[0].Extra.id | Should -Be 'id498'
            $Batch[0].RunStamp | Should -Be '20261101T000000Z'
            @(Get-CIPPCloudBackupJobItemBatch -Context $Context -Offset 1200 -Count 20).Count | Should -Be 3
            @(Get-CIPPCloudBackupJobItemBatch -Context $Context -Offset 1203 -Count 20).Count | Should -Be 0
        }

        It 'reuses the last part read instead of downloading it again' {
            Mock Get-CIPPCloudBackupOwnerListing { foreach ($i in 0..99) { New-Entry -Index $i } }
            $Context = New-Context
            $null = Save-CIPPCloudBackupJobManifest -Context $Context
            foreach ($Offset in 0, 20, 40, 60, 80, 100) { $null = Get-CIPPCloudBackupJobItemBatch -Context $Context -Offset $Offset -Count 20 }
            $script:ManifestPartReads | Should -Be 1
        }

        It 'selects keys (with deleted items) and folders, and writes an entry selected twice once' {
            Mock Get-CIPPCloudBackupOwnerListing { New-Entry -Index 1; New-Entry -Index 2 } -ParameterFilter { $Key }
            Mock Get-CIPPCloudBackupOwnerListing { New-Entry -Index 2; New-Entry -Index 3 -Path 'Inbox/Sub' } -ParameterFilter { $Path -eq 'Inbox' }
            Mock Get-CIPPCloudBackupOwnerListing { New-Entry -Index 4 -Path 'Archive' } -ParameterFilter { $Path -eq 'Archive' }
            $Context = New-Context

            $Manifest = Save-CIPPCloudBackupJobManifest -Context $Context -Keys @('items/f/1.fts', 'items/f/2.fts') -Paths @('/Inbox/', 'Archive')

            $Manifest.Items | Should -Be 4
            Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 1 -Exactly -ParameterFilter { $Key -and $IncludeDeleted -and $Stream -and @($Key).Count -eq 2 }
            Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 1 -Exactly -ParameterFilter { $Path -eq 'Inbox' -and $Recurse -and $IncludeFolders -and $Stream }
            @((Get-CIPPCloudBackupJobItemBatch -Context $Context -Offset 0 -Count 10).Key) | Should -Be @('items/f/1.fts', 'items/f/2.fts', 'items/f/3.fts', 'items/f/4.fts')
        }

        It 'writes an empty manifest when nothing is selected, and reads the manifest of another job' {
            Mock Get-CIPPCloudBackupOwnerListing { }
            $Manifest = Save-CIPPCloudBackupJobManifest -Context (New-Context -JobId 'preview-1')
            $Manifest.Items | Should -Be 0
            $Manifest.Parts | Should -Be 1
            @(Get-CIPPCloudBackupJobItemBatch -Context (New-Context -JobId 'apply-1' -ManifestJobId 'preview-1') -Offset 0 -Count 20).Count | Should -Be 0
            $script:Store.ContainsKey('p1/jobs/preview-1/items/00000.jsonl.gz') | Should -BeTrue
        }
    }

    Context 'Downloads in parts' {
        It 'splits plain data into parts that join to the original' {
            $Plain = New-Plain -Length 1000
            $script:Store['plain'] = @{ Bytes = $Plain; ContentType = 'application/octet-stream' }
            $Result = Read-Parts -Key 'plain' -PartSize 300
            $Result.Parts | Should -Be 4
            $Result.Size | Should -Be 1000
            [Convert]::ToHexString($Result.Bytes) | Should -Be ([Convert]::ToHexString($Plain))
        }

        It 'decrypts CIPPENC2 data of <Length> bytes part by part' -ForEach @(
            @{ Length = 0; Parts = 1 }, @{ Length = 63; Parts = 1 }, @{ Length = 64; Parts = 1 }, @{ Length = 192; Parts = 1 }
            @{ Length = 193; Parts = 1 }, @{ Length = 640; Parts = 4 }, @{ Length = 1000; Parts = 5 }
        ) {
            $Plain = New-Plain -Length $Length
            $Out = [System.IO.MemoryStream]::new()
            $null = Protect-CIPPCloudBackupStream -InputStream ([System.IO.MemoryStream]::new($Plain)) -OutputStream $Out -KeyId $script:KeyId -Key ([byte[]]$script:Key.Clone()) -ChunkSize 64
            $script:Store['enc'] = @{ Bytes = $Out.ToArray(); ContentType = 'application/octet-stream' }

            $Result = Read-Parts -Key 'enc' -PartSize 200

            $Result.Parts | Should -Be $Parts
            $Result.Size | Should -Be $Length
            [Convert]::ToHexString($Result.Bytes) | Should -Be ([Convert]::ToHexString($Plain))
        }

        It 'downloads only the stored bytes of the requested part' {
            $Plain = New-Plain -Length 6400
            $Out = [System.IO.MemoryStream]::new()
            $null = Protect-CIPPCloudBackupStream -InputStream ([System.IO.MemoryStream]::new($Plain)) -OutputStream $Out -KeyId $script:KeyId -Key ([byte[]]$script:Key.Clone()) -ChunkSize 64
            $script:Store['enc'] = @{ Bytes = $Out.ToArray(); ContentType = 'application/octet-stream' }

            $Part = Read-CIPPCloudBackupObjectPart -Destination $script:Destination -Key 'enc' -Part 5 -PartSize 640

            $Part.Body.Length | Should -Be 640
            [Convert]::ToHexString($Part.Body) | Should -Be ([Convert]::ToHexString($Plain[3200..3839]))
            $script:BytesRead | Should -Be (100 + 10 * 80)
        }

        It 'rejects damaged data in a middle part' {
            $Plain = New-Plain -Length 640
            $Out = [System.IO.MemoryStream]::new()
            $null = Protect-CIPPCloudBackupStream -InputStream ([System.IO.MemoryStream]::new($Plain)) -OutputStream $Out -KeyId $script:KeyId -Key ([byte[]]$script:Key.Clone()) -ChunkSize 64
            $Bytes = $Out.ToArray()
            $Bytes[100 + 4 * 80 + 3] = $Bytes[100 + 4 * 80 + 3] -bxor 1
            $script:Store['enc'] = @{ Bytes = $Bytes; ContentType = 'application/octet-stream' }

            { Read-CIPPCloudBackupObjectPart -Destination $script:Destination -Key 'enc' -Part 1 -PartSize 256 } | Should -Throw '*changed or is damaged*'
        }

        It 'decrypts CIPPENC1 data, rejects a part that does not exist and returns null for a missing object' {
            $Plain = New-Plain -Length 500
            $script:Store['enc1'] = @{ Bytes = (Protect-CIPPCloudBackupData -Bytes $Plain -KeyId $script:KeyId -Key ([byte[]]$script:Key.Clone())); ContentType = 'application/octet-stream' }
            $Result = Read-Parts -Key 'enc1' -PartSize 200
            $Result.Parts | Should -Be 3
            [Convert]::ToHexString($Result.Bytes) | Should -Be ([Convert]::ToHexString($Plain))

            { Read-CIPPCloudBackupObjectPart -Destination $script:Destination -Key 'enc1' -Part 3 -PartSize 200 } | Should -Throw -ExceptionType ([System.ArgumentException])
            Read-CIPPCloudBackupObjectPart -Destination $script:Destination -Key 'missing' | Should -BeNullOrEmpty
        }
    }

    Context 'Job context' {
        It 'builds the restore context from a job row' {
            Mock Get-CIPPCloudBackupPolicy { [pscustomobject]@{ Id = 'p1'; DestinationId = 'd1' } }
            Mock Get-CIPPCloudBackupDestination { $script:Destination }
            Mock Get-CIPPTenantLookup { @{ c1 = [pscustomobject]@{ customerId = 'c1'; defaultDomainName = 'contoso.com' } } }
            $Job = [pscustomobject]@{
                RowKey = 'job-2'; Type = 'Restore'; PolicyId = 'p1'; SourceTenantId = 'c1'; Workload = 'onedrive'; SourceOwnerId = "u/1'x"; SourceOwnerType = 'User'; SourceRemoved = $true
                TargetOwnerId = 'u2'; TargetOwnerType = 'User'; TargetUserPrincipalName = 'b@contoso.com'; TargetSiteId = ''; TargetDriveId = 'd2'; Location = 'Original'
                RestoredFolderName = 'Restored 2026-11-20 10:00'; ConflictAction = 'Copy'; AsOf = ''; RunStamp = '20261101T000000Z'; DataKeyId = $script:KeyId; ManifestJobId = 'job-1'
            }

            $Context = Get-CIPPCloudBackupJobContext -Job $Job

            $Context.Apply | Should -BeTrue
            $Context.TenantFilter | Should -Be 'contoso.com'
            $Context.OwnerPrefix | Should -Be 'p1/c1/onedrive/u_1_x/'
            $Context.SourceRemoved | Should -BeTrue
            $Context.Target.DriveId | Should -Be 'd2'
            $Context.Target.SiteId | Should -BeNullOrEmpty
            $Context.KeyId | Should -Be $script:KeyId
            $Context.Key.Length | Should -Be 32
            $Context.ManifestJobId | Should -Be 'job-1'
            $Context.RestoredFolderName | Should -Be 'Restored 2026-11-20 10:00'
        }
    }
}
