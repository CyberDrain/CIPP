BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup'
    Add-Type -Path (Join-Path $BackendRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    function New-GraphGetRequest { param($uri, $tenantid, $asapp) }
    function New-GraphPOSTRequest { param($uri, $tenantid, $body, $type, $AsApp, $contentType) }
    function New-GraphBulkRequest { param($tenantid, $asapp, $Version, $Requests) }
    function Get-CIPPCloudBackupJobItemBatch { param($Context, $Offset, $Count) }
    function Receive-CIPPCloudBackupObjectStream { param($Destination, $Key, $VersionId, $Offset, $Length, $OutStream) }
    function Get-CIPPCloudBackupKey { param($KeyId) }

    foreach ($Name in 'Invoke-CIPPCloudBackupDriveRestoreStep', 'Invoke-CIPPCloudBackupOneDriveRestoreStep', 'Invoke-CIPPCloudBackupSharePointRestoreStep', 'Restore-CIPPCloudBackupDriveFile', 'Unprotect-CIPPCloudBackupStreamBlock', 'Unprotect-CIPPCloudBackupStream', 'Unprotect-CIPPCloudBackupData', 'Protect-CIPPCloudBackupStream', 'Read-CIPPCloudBackupStreamBlock') {
        . (Join-Path $Folder "$Name.ps1")
    }

    if (-not ('CippTestRestorePattern' -as [type])) {
        Add-Type -TypeDefinition @'
public sealed class CippTestRestorePattern : System.IO.Stream
{
    private readonly long _length;
    private long _position;
    public CippTestRestorePattern(long length) { _length = length; }
    public static void Fill(byte[] buffer, long position, int count)
    {
        for (int i = 0; i < count; i++) { buffer[i] = (byte)(((position + i) * 13 + 5) % 253); }
    }
    public override int Read(byte[] buffer, int offset, int count)
    {
        int n = (int)System.Math.Min(count, _length - _position);
        byte[] part = new byte[n];
        Fill(part, _position, n);
        System.Array.Copy(part, 0, buffer, offset, n);
        _position += n;
        return n;
    }
    public override bool CanRead { get { return true; } }
    public override bool CanSeek { get { return false; } }
    public override bool CanWrite { get { return false; } }
    public override long Length { get { throw new System.NotSupportedException(); } }
    public override long Position { get { return _position; } set { throw new System.NotSupportedException(); } }
    public override void Flush() { }
    public override long Seek(long offset, System.IO.SeekOrigin origin) { throw new System.NotSupportedException(); }
    public override void SetLength(long value) { throw new System.NotSupportedException(); }
    public override void Write(byte[] buffer, int offset, int count) { throw new System.NotSupportedException(); }
}
'@
    }

    function Get-PatternHash([long]$Length) {
        [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([CippTestRestorePattern]::new($Length)))
    }

    $script:EncKeyId = [guid]::NewGuid().ToString()
    $script:EncKey = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)

    $Probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $Probe.Start()
    $Port = $Probe.LocalEndpoint.Port
    $Probe.Stop()
    $script:BaseUrl = "http://127.0.0.1:$Port"
    $script:Shared = [hashtable]::Synchronized(@{})
    $script:Listener = [System.Net.HttpListener]::new()
    $script:Listener.Prefixes.Add("$script:BaseUrl/")
    $script:Listener.Start()
    $script:Server = [powershell]::Create()
    $null = $script:Server.AddScript({
            param($Listener, $Shared)
            $Buffer = [byte[]]::new(64KB)
            while ($Listener.IsListening) {
                try { $Ctx = $Listener.GetContext() } catch { break }
                $Request = $Ctx.Request
                $Response = $Ctx.Response
                $Session = ($Request.Url.AbsolutePath -split '/')[-1]
                try {
                    if ($Request.HttpMethod -eq 'DELETE') {
                        $Shared.Deleted.Add($Session)
                        $Response.StatusCode = 204
                        $Response.Close()
                        continue
                    }
                    if (-not $Shared.Hashes.ContainsKey($Session)) { $Shared.Hashes[$Session] = [System.Security.Cryptography.IncrementalHash]::CreateHash('SHA256') }
                    $Length = 0
                    while (($Read = $Request.InputStream.Read($Buffer, 0, $Buffer.Length)) -gt 0) {
                        $Shared.Hashes[$Session].AppendData($Buffer, 0, $Read)
                        $Length += $Read
                    }
                    $Range = [string]$Request.Headers['Content-Range']
                    $null = $Range -match '^bytes (\d+)-(\d+)/(\d+)$'
                    $Shared.Puts.Add([pscustomobject]@{ Session = $Session; Range = $Range; Length = $Length; Auth = [string]$Request.Headers['Authorization']; ReadAhead = [int64]$Shared.ReadBytes - ([int64]$Matches[2] + 1) })
                    $Name = $Shared.Names[$Session]
                    if ($Shared.Reject -contains $Name) {
                        $Response.StatusCode = 400
                        $Body = [System.Text.Encoding]::UTF8.GetBytes('{"error":{"code":"invalidRequest"}}')
                    } elseif ([int64]$Matches[2] + 1 -eq [int64]$Matches[3]) {
                        $Response.StatusCode = 201
                        $Body = [System.Text.Encoding]::UTF8.GetBytes((ConvertTo-Json -InputObject @{ id = "item-$Session"; name = $Name } -Compress))
                    } else {
                        $Response.StatusCode = 202
                        $Body = [System.Text.Encoding]::UTF8.GetBytes('{"nextExpectedRanges":[]}')
                    }
                    $Response.OutputStream.Write($Body, 0, $Body.Length)
                    $Response.Close()
                } catch {
                    try { $Response.Abort() } catch { }
                }
            }
        }).AddArgument($script:Listener).AddArgument($script:Shared)
    $script:ServerHandle = $script:Server.BeginInvoke()

    function New-RestoreContext {
        param([bool]$Apply = $false, $ConflictAction = 'Skip', $Location = 'RestoredFolder', $Workload = 'onedrive', $TargetOwnerId = 'user1', $TargetDriveId = 'd1', [bool]$Removed = $false)
        [pscustomobject]@{
            JobId = 'job1'; PolicyId = 'p'; TenantId = 't'; TenantFilter = 'contoso.onmicrosoft.com'; Workload = $Workload
            SourceOwnerId = 'user1'; SourceOwnerType = 'User'; SourceRemoved = $Removed
            Target = @{ OwnerId = $TargetOwnerId; OwnerType = 'User'; UserPrincipalName = 'target@contoso.com'; SiteId = $null; DriveId = $TargetDriveId }
            Location = $Location; RestoredFolderName = 'Restored 2026-11-20 14:30'; ConflictAction = $ConflictAction
            AsOf = '20261120T000000Z'; RunStamp = '20261120T000000Z'; Destination = [pscustomobject]@{ Provider = 'AzureBlob' }
            KeyId = $null; Key = $null; OwnerPrefix = "p/c/$Workload/user1/"; Apply = $Apply
        }
    }

    function New-Entry {
        param($Name, $Path = '/', $Type = 'file', $Hash = 'h-source', $DriveId = 'd1', [bool]$Deleted = $false, $Size = 10)
        [pscustomobject]@{
            Key = "items/$DriveId/$Name"; Path = $Path; Name = $Name; Type = $Type; Size = $Size; Modified = '2026-11-01T10:00:00Z'; VersionId = 'v1'; Deleted = $Deleted
            Extra = [pscustomobject]@{ driveId = $DriveId; driveName = 'Shared Documents'; parentId = 'parent'; hash = $Hash }; RunStamp = '20261120T000000Z'
        }
    }

    function New-ExistingFile([string]$Hash = 'h-other') {
        [pscustomobject]@{ id = "existing-$Hash"; name = 'x'; file = [pscustomobject]@{ hashes = [pscustomobject]@{ quickXorHash = $Hash } } }
    }

    function Get-UploadNames { @($script:Shared.Posts.Where({ $_.Uri -match 'createUploadSession' }).ForEach({ [uri]::UnescapeDataString(($_.Uri -split ':/')[-2]) })) }
}

AfterAll {
    $script:Listener.Stop()
    $script:Listener.Close()
    $script:Server.Dispose()
}

Describe 'File restore step' {
    BeforeEach {
        $script:Shared.Posts = [System.Collections.Generic.List[object]]::new()
        $script:Shared.Puts = [System.Collections.Generic.List[object]]::new()
        $script:Shared.Deleted = [System.Collections.Generic.List[string]]::new()
        $script:Shared.Hashes = [hashtable]::Synchronized(@{})
        $script:Shared.Names = [hashtable]::Synchronized(@{})
        $script:Shared.Reject = @()
        $script:Shared.ReadBytes = 0
        $script:Shared.Reads = [System.Collections.Generic.List[object]]::new()
        $script:Existing = @{}
        $script:FolderConflicts = @()
        $script:Blobs = @{}
        $script:Entries = @()

        Mock Get-CIPPCloudBackupKey { , ([byte[]]$script:EncKey.Clone()) }
        Mock Get-CIPPCloudBackupJobItemBatch {
            $Last = [Math]::Min($Offset + $Count, $script:Entries.Count) - 1
            if ($Offset -le $Last) { $script:Entries[$Offset..$Last] }
        }
        Mock New-GraphGetRequest {
            if ($uri -match '/users/') { return [pscustomobject]@{ userPrincipalName = 'jane@contoso.com' } }
            $Path = [uri]::UnescapeDataString((($uri -replace '^.*/root:', '') -replace '\?.*$', ''))
            $script:Existing["$(($uri -split '/drives/')[1].Split('/')[0])|$Path"]
        }
        Mock New-GraphBulkRequest {
            foreach ($Request in $Requests) {
                $Drive = $Request.url.Split('/')[1]
                $Path = [uri]::UnescapeDataString((($Request.url -replace '^drives/[^/]+/root:?', '') -replace '\?.*$', ''))
                $Hit = $script:Existing["$Drive|$Path"]
                if ($Hit) { @{ id = $Request.id; status = 200; body = $Hit } } else { @{ id = $Request.id; status = 404; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'itemNotFound' } } } }
            }
        }
        Mock New-GraphPOSTRequest {
            $script:Shared.Posts.Add([pscustomobject]@{ Uri = $uri; Body = $body; Type = $type })
            if ($uri -match 'createUploadSession$') {
                $Session = "$($script:Shared.Posts.Count)"
                $script:Shared.Names[$Session] = [uri]::UnescapeDataString(($uri -split ':/')[-2])
                return [pscustomobject]@{ uploadUrl = "$script:BaseUrl/upload/$Session" }
            }
            if ($uri -match '/children$') {
                $Folder = ConvertFrom-Json $body
                if ($script:FolderConflicts -contains $Folder.name) { throw 'nameAlreadyExists: an item with that name already exists' }
                return [pscustomobject]@{ id = "id-$($Folder.name)" }
            }
            if ($type -eq 'PUT') { return [pscustomobject]@{ id = 'empty-item'; name = 'empty.txt' } }
        }
        Mock Receive-CIPPCloudBackupObjectStream {
            $Blob = $script:Blobs[$Key]
            if ($null -eq $Blob) { return $null }
            $Stop = if ($Length -lt $Blob.Size - $Offset) { $Offset + $Length } else { $Blob.Size }
            $Count = [int]($Stop - $Offset)
            $script:Shared.Reads.Add([pscustomobject]@{ Key = $Key; VersionId = $VersionId; Offset = $Offset; Count = $Count })
            if ($Count -gt 0) {
                $Part = [byte[]]::new($Count)
                if ($Blob.Data) { [System.Array]::Copy($Blob.Data, $Offset, $Part, 0, $Count) } else { [CippTestRestorePattern]::Fill($Part, $Offset, $Count) }
                $OutStream.Write($Part, 0, $Count)
            }
            $script:Shared.ReadBytes = $Stop
            [pscustomobject]@{ Key = $Key; VersionId = $VersionId; Bytes = [int64]$Blob.Size }
        }
    }

    It 'previews every conflict mode from target reads only' -ForEach @(
        @{ Mode = 'Skip'; Actions = @('Create', 'Skip', 'Skip', 'Create', 'Skip', 'NotRestorable') }
        @{ Mode = 'Overwrite'; Actions = @('Create', 'Overwrite', 'Skip', 'Create', 'Skip', 'NotRestorable') }
        @{ Mode = 'Copy'; Actions = @('Create', 'Copy', 'Skip', 'Create', 'Skip', 'NotRestorable') }
    ) {
        $script:Entries = @(
            New-Entry 'new.txt' '/Docs'
            New-Entry 'changed.txt' '/Docs'
            New-Entry 'same.txt' '/Docs' -Hash 'h-same'
            New-Entry 'Empty' '/Docs' -Type 'folder'
            New-Entry 'Existing' '/Docs' -Type 'folder'
            New-Entry 'gone.txt' '/Docs' -Deleted $true
        )
        $script:Existing['d1|/Docs/changed.txt'] = New-ExistingFile
        $script:Existing['d1|/Docs/same.txt'] = New-ExistingFile 'h-same'
        $script:Existing['d1|/Docs/Existing'] = [pscustomobject]@{ id = 'folder-existing'; folder = @{ childCount = 0 } }

        $Step = Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext -ConflictAction $Mode -Location 'Original')

        $Step.Done | Should -BeTrue
        $Step.Bytes | Should -Be 0
        $Step.Results.Action | Should -Be $Actions
        $Step.Results.Status | Should -Be @('Planned', $(if ($Mode -eq 'Skip') { 'Skipped' } else { 'Planned' }), 'Skipped', 'Planned', 'Skipped', 'Skipped')
        $Step.Results[1].TargetPath | Should -Be $(if ($Mode -eq 'Copy') { '/Docs/changed (restored 2026-11-20 14-30).txt' } else { '/Docs/changed.txt' })
        $Step.Results[3].TargetPath | Should -Be '/Docs/Empty'
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
        Should -Invoke Receive-CIPPCloudBackupObjectStream -Times 0 -Exactly
        $script:Shared.Puts.Count | Should -Be 0
    }

    It 'streams a 45 MiB file in 320 KiB-aligned fragments without the bearer token and without reading ahead' {
        $script:Entries = @(New-Entry 'big.bin' '/')
        $script:Blobs['p/c/onedrive/user1/items/d1/big.bin'] = @{ Size = 45MB }

        $Step = Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext -Apply $true -Location 'Original')

        $Step.Results[0].Status | Should -Be 'Succeeded'
        $Step.Results[0].TargetPath | Should -Be '/big.bin'
        $Step.Bytes | Should -Be 45MB
        $Puts = @($script:Shared.Puts)
        $Puts.Range | Should -Be @(
            "bytes 0-$(10MB - 1)/$(45MB)", "bytes $(10MB)-$(20MB - 1)/$(45MB)", "bytes $(20MB)-$(30MB - 1)/$(45MB)", "bytes $(30MB)-$(40MB - 1)/$(45MB)", "bytes $(40MB)-$(45MB - 1)/$(45MB)"
        )
        foreach ($Put in $Puts) {
            $Put.Auth | Should -BeNullOrEmpty
            $Put.Length % 320KB | Should -Be 0
            $Put.ReadAhead | Should -BeLessOrEqual 8MB
        }
        foreach ($Read in $script:Shared.Reads) { $Read.Count | Should -BeLessOrEqual 8MB }
        $script:Shared.Reads.VersionId | Select-Object -Unique | Should -Be 'v1'
        [Convert]::ToHexString($script:Shared.Hashes[$Puts[0].Session].GetHashAndReset()) | Should -Be (Get-PatternHash 45MB)
        $Session = ConvertFrom-Json $script:Shared.Posts[0].Body
        $Session.item.'@microsoft.graph.conflictBehavior' | Should -Be 'fail'
        $script:Shared.Posts[0].Body | Should -BeLike '*"lastModifiedDateTime":"2026-11-01T10:00:00Z"*'
        $script:Shared.Posts[0].Uri | Should -Be 'https://graph.microsoft.com/v1.0/drives/d1/items/root:/big.bin:/createUploadSession'
    }

    It 'decrypts an encrypted file while streaming it, across frames that straddle storage reads' {
        $Cipher = [System.IO.MemoryStream]::new()
        $null = Protect-CIPPCloudBackupStream -InputStream ([CippTestRestorePattern]::new(23MB + 123)) -OutputStream $Cipher -KeyId $EncKeyId -Key $EncKey -ChunkSize 3MB
        $script:Entries = @(New-Entry 'secret.docx' '/')
        $script:Blobs['p/c/onedrive/user1/items/d1/secret.docx'] = @{ Size = $Cipher.Length; Data = $Cipher.ToArray() }

        $Step = Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext -Apply $true -Location 'Original')

        $Step.Results[0].Status | Should -Be 'Succeeded'
        $Step.Bytes | Should -Be (23MB + 123)
        $Puts = @($script:Shared.Puts)
        $Puts.Count | Should -Be 3
        $Puts[2].Range | Should -Be "bytes $(20MB)-$(23MB + 122)/$(23MB + 123)"
        foreach ($Put in $Puts) { $Put.ReadAhead | Should -BeLessOrEqual 9MB }
        [Convert]::ToHexString($script:Shared.Hashes[$Puts[0].Session].GetHashAndReset()) | Should -Be (Get-PatternHash (23MB + 123))
    }

    It 'fails a damaged encrypted file and cancels its upload session' {
        $Cipher = [System.IO.MemoryStream]::new()
        $null = Protect-CIPPCloudBackupStream -InputStream ([CippTestRestorePattern]::new(12MB)) -OutputStream $Cipher -KeyId $EncKeyId -Key $EncKey -ChunkSize 1MB
        $Data = $Cipher.ToArray()
        $Data[$Data.Length - 100] = $Data[$Data.Length - 100] -bxor 1
        $script:Entries = @(New-Entry 'broken.bin' '/'; New-Entry 'small.txt' '/')
        $script:Blobs['p/c/onedrive/user1/items/d1/broken.bin'] = @{ Size = $Data.Length; Data = $Data }
        $script:Blobs['p/c/onedrive/user1/items/d1/small.txt'] = @{ Size = 100 }

        $Step = Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext -Apply $true -Location 'Original')

        $Step.Results[0].Status | Should -Be 'Failed'
        $Step.Results[0].Message | Should -BeLike '*changed or is damaged*'
        $Step.Results[1].Status | Should -Be 'Succeeded'
        $script:Shared.Deleted | Should -Contain '1'
    }

    It 'isolates per-file failures: a refused upload and a missing stored version do not stop the batch' {
        $script:Entries = @(New-Entry 'refused.txt' '/'; New-Entry 'missing.txt' '/'; New-Entry 'fine.txt' '/')
        $script:Blobs['p/c/onedrive/user1/items/d1/refused.txt'] = @{ Size = 50 }
        $script:Blobs['p/c/onedrive/user1/items/d1/fine.txt'] = @{ Size = 50 }
        $script:Shared.Reject = @('refused.txt')

        $Step = Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext -Apply $true -Location 'Original')

        $Step.Results.Status | Should -Be @('Failed', 'Failed', 'Succeeded')
        $Step.Results[0].Message | Should -BeLike '*status 400*'
        $Step.Results[1].Message | Should -BeLike '*no longer in the backup storage*'
        $script:Shared.Deleted | Should -Be @('1')
        $Step.Bytes | Should -Be 50
    }

    It 'applies <Mode> to an existing file' -ForEach @(
        @{ Mode = 'Overwrite'; Behavior = 'replace'; Name = 'report.docx'; Path = '/Docs/report.docx' }
        @{ Mode = 'Copy'; Behavior = 'rename'; Name = 'report (restored 2026-11-20 14-30).docx'; Path = '/Docs/report (restored 2026-11-20 14-30).docx' }
    ) {
        $script:Entries = @(New-Entry 'report.docx' '/Docs')
        $script:Existing['d1|/Docs/report.docx'] = New-ExistingFile
        $script:Existing['d1|/Docs'] = [pscustomobject]@{ id = 'docs-id'; folder = @{} }
        $script:Blobs['p/c/onedrive/user1/items/d1/report.docx'] = @{ Size = 1000 }

        $Step = Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext -Apply $true -ConflictAction $Mode -Location 'Original')

        $Step.Results[0].Action | Should -Be $Mode
        $Step.Results[0].Status | Should -Be 'Succeeded'
        $Step.Results[0].TargetPath | Should -Be $Path
        Get-UploadNames | Should -Be @($Name)
        $script:Shared.Posts[0].Uri | Should -BeLike 'https://graph.microsoft.com/v1.0/drives/d1/items/docs-id:/*'
        (ConvertFrom-Json $script:Shared.Posts[0].Body).item.'@microsoft.graph.conflictBehavior' | Should -Be $Behavior
    }

    It 'leaves an existing file alone in Skip mode, and when the target already has the same content in any mode' {
        $script:Entries = @(New-Entry 'keep.txt' '/'; New-Entry 'same.txt' '/' -Hash 'h-same')
        $script:Existing['d1|/keep.txt'] = New-ExistingFile
        $script:Existing['d1|/same.txt'] = New-ExistingFile 'h-same'
        $script:Blobs['p/c/onedrive/user1/items/d1/keep.txt'] = @{ Size = 3 }
        foreach ($Mode in 'Skip', 'Overwrite', 'Copy') {
            $Step = Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext -Apply $true -ConflictAction $Mode -Location 'Original')
            $Step.Results[1].Status | Should -Be 'Skipped'
            $Step.Results[1].Message | Should -BeLike '*same content*'
        }
        Get-UploadNames | Should -Be @('keep.txt', 'keep (restored 2026-11-20 14-30).txt')
    }

    It 'skips a copy that an earlier attempt of the same job already restored' {
        $script:Entries = @(New-Entry 'a.txt' '/')
        $script:Existing['d1|/a.txt'] = New-ExistingFile
        $script:Existing['d1|/a (restored 2026-11-20 14-30).txt'] = New-ExistingFile 'h-source'

        $Step = Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext -Apply $true -ConflictAction 'Copy' -Location 'Original')

        $Step.Results[0].Status | Should -Be 'Skipped'
        Should -Invoke New-GraphPOSTRequest -Times 0 -Exactly
    }

    It 'reports a file that appeared after the check as skipped in Skip mode' {
        $script:Entries = @(New-Entry 'race.txt' '/')
        $script:Blobs['p/c/onedrive/user1/items/d1/race.txt'] = @{ Size = 10 }
        Mock Restore-CIPPCloudBackupDriveFile {
            $Conflict = [System.InvalidOperationException]::new('exists')
            $Conflict.Data['Conflict'] = $true
            throw $Conflict
        }

        $Step = Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext -Apply $true -Location 'Original')

        $Step.Results[0].Action | Should -Be 'Skip'
        $Step.Results[0].Status | Should -Be 'Skipped'
    }

    It 'recreates the folder path under the restored folder once, including empty folders' {
        $script:Entries = @(
            New-Entry 'one.txt' '/A/B'
            New-Entry 'two.txt' '/A/B'
            New-Entry 'Empty' '/A' -Type 'folder'
            New-Entry 'root.txt' '/'
        )
        foreach ($Name in 'one.txt', 'two.txt', 'root.txt') { $script:Blobs["p/c/onedrive/user1/items/d1/$Name"] = @{ Size = 5 } }
        $script:FolderConflicts = @('A')
        $script:Existing['d1|/Restored 2026-11-20 14-30/A'] = [pscustomobject]@{ id = 'existing-A'; folder = @{} }

        $Step = Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext -Apply $true)

        $Step.Results.Status | Should -Be @('Succeeded', 'Succeeded', 'Succeeded', 'Succeeded')
        $Step.Results.TargetPath | Should -Be @('/Restored 2026-11-20 14-30/A/B/one.txt', '/Restored 2026-11-20 14-30/A/B/two.txt', '/Restored 2026-11-20 14-30/A/Empty', '/Restored 2026-11-20 14-30/root.txt')
        $Folders = @($script:Shared.Posts.Where({ $_.Uri -match '/children$' }))
        $Folders.Uri | Should -Be @(
            'https://graph.microsoft.com/v1.0/drives/d1/items/root/children'
            'https://graph.microsoft.com/v1.0/drives/d1/items/id-Restored 2026-11-20 14-30/children'
            'https://graph.microsoft.com/v1.0/drives/d1/items/existing-A/children'
            'https://graph.microsoft.com/v1.0/drives/d1/items/existing-A/children'
        )
        @($Folders.ForEach({ (ConvertFrom-Json $_.Body).name })) | Should -Be @('Restored 2026-11-20 14-30', 'A', 'B', 'Empty')
        (ConvertFrom-Json $Folders[0].Body).'@microsoft.graph.conflictBehavior' | Should -Be 'fail'
        @($script:Shared.Posts.Where({ $_.Uri -match 'createUploadSession' }).Uri) | Should -Be @(
            'https://graph.microsoft.com/v1.0/drives/d1/items/id-B:/one.txt:/createUploadSession'
            'https://graph.microsoft.com/v1.0/drives/d1/items/id-B:/two.txt:/createUploadSession'
            'https://graph.microsoft.com/v1.0/drives/d1/items/id-Restored 2026-11-20 14-30:/root.txt:/createUploadSession'
        )
    }

    It 'restores <Name>' -ForEach @(
        @{ Name = "to the owner's current OneDrive at the original path"; Workload = 'onedrive'; Target = 'user1'; TargetDrive = 'd-new'; Location = 'Original'; Removed = $false; Drive = 'd-new'; Path = '/Docs/f.txt' }
        @{ Name = "to another user's OneDrive under the source user's name"; Workload = 'onedrive'; Target = 'user2'; TargetDrive = 'd2'; Location = 'Original'; Removed = $false; Drive = 'd2'; Path = '/Restored 2026-11-20 14-30/jane@contoso.com/Docs/f.txt' }
        @{ Name = 'a removed owner to another user'; Workload = 'onedrive'; Target = 'user1'; TargetDrive = 'd2'; Location = 'RestoredFolder'; Removed = $true; Drive = 'd2'; Path = '/Restored 2026-11-20 14-30/jane@contoso.com/Docs/f.txt' }
        @{ Name = 'a SharePoint library in place'; Workload = 'sharepoint'; Target = 'user1'; TargetDrive = $null; Location = 'RestoredFolder'; Removed = $false; Drive = 'd1'; Path = '/Restored 2026-11-20 14-30/Docs/f.txt' }
        @{ Name = "a SharePoint library to a user's OneDrive under the library name"; Workload = 'sharepoint'; Target = 'user2'; TargetDrive = 'd2'; Location = 'Original'; Removed = $false; Drive = 'd2'; Path = '/Restored 2026-11-20 14-30/Shared Documents/Docs/f.txt' }
    ) {
        $script:Entries = @(New-Entry 'f.txt' '/Docs')
        $script:Existing["$Drive|$($Path.Substring(0, $Path.LastIndexOf('/')))"] = [pscustomobject]@{ id = 'parent-id'; folder = @{} }
        $Context = New-RestoreContext -Apply $true -Workload $Workload -TargetOwnerId $Target -TargetDriveId $TargetDrive -Location $Location -Removed $Removed
        $script:Blobs["$($Context.OwnerPrefix)items/d1/f.txt"] = @{ Size = 7 }

        $Step = if ($Workload -eq 'sharepoint') { Invoke-CIPPCloudBackupSharePointRestoreStep -Context $Context } else { Invoke-CIPPCloudBackupOneDriveRestoreStep -Context $Context }

        $Step.Results[0].Status | Should -Be 'Succeeded'
        $Step.Results[0].TargetPath | Should -Be $Path
        $script:Shared.Posts[0].Uri | Should -Be "https://graph.microsoft.com/v1.0/drives/$Drive/items/parent-id:/f.txt:/createUploadSession"
    }

    It 'refuses another-user restores when the target has no OneDrive' {
        $script:Entries = @(New-Entry 'f.txt' '/')
        { Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext -TargetOwnerId 'user2' -TargetDriveId $null) } | Should -Throw -ExceptionType ([System.ArgumentException])
    }

    It 'uploads an empty file with a plain PUT' {
        $script:Entries = @(New-Entry 'empty.txt' '/')
        $script:Blobs['p/c/onedrive/user1/items/d1/empty.txt'] = @{ Size = 0 }

        $Step = Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext -Apply $true -Location 'Original')

        $Step.Results[0].Status | Should -Be 'Succeeded'
        $script:Shared.Posts[0].Type | Should -Be 'PUT'
        $script:Shared.Posts[0].Uri | Should -Be 'https://graph.microsoft.com/v1.0/drives/d1/items/root:/empty.txt:/content?@microsoft.graph.conflictBehavior=fail'
    }

    It 'pages through the job in batches of 20 and resumes from the saved offset' {
        $script:Entries = @(foreach ($i in 1..25) { New-Entry "f$i.txt" '/' })

        $First = Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext)
        $First.Results.Count | Should -Be 20
        $First.Done | Should -BeFalse
        $First.State.Offset | Should -Be 20

        $Second = Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext) -State ([pscustomobject]$First.State)
        $Second.Results.Count | Should -Be 5
        $Second.Results[0].Name | Should -Be 'f21.txt'
        $Second.Done | Should -BeTrue
    }

    It 'stops a batch early once 256 MiB has been uploaded' {
        $script:Entries = @(New-Entry 'big.bin' '/'; New-Entry 'next.txt' '/')
        Mock Restore-CIPPCloudBackupDriveFile { [pscustomobject]@{ Id = 'x'; Name = $Name; Bytes = [int64]300MB } }

        $Step = Invoke-CIPPCloudBackupOneDriveRestoreStep -Context (New-RestoreContext -Apply $true -Location 'Original')

        $Step.Results.Count | Should -Be 1
        $Step.State.Offset | Should -Be 1
        $Step.Done | Should -BeFalse
    }
}

Describe 'Unprotect-CIPPCloudBackupStreamBlock' {
    BeforeEach {
        Mock Get-CIPPCloudBackupKey { , ([byte[]]$script:EncKey.Clone()) }
    }

    It 'decrypts pieces split at <Split> bytes the same as the whole stream' -ForEach @(@{ Split = 99 }, @{ Split = 4099 }, @{ Split = 64KB + 16 }, @{ Split = 1MB + 7 }) {
        $Cipher = [System.IO.MemoryStream]::new()
        $null = Protect-CIPPCloudBackupStream -InputStream ([CippTestRestorePattern]::new(64KB * 3)) -OutputStream $Cipher -KeyId $EncKeyId -Key $EncKey -ChunkSize 64KB
        $Data = $Cipher.ToArray()
        $Decryptor = @{}
        $Out = [System.IO.MemoryStream]::new()
        for ($i = 0; $i -lt $Data.Length; $i += $Split) {
            $Count = [Math]::Min($Split, $Data.Length - $i)
            $Piece = [byte[]]::new($Count)
            [System.Array]::Copy($Data, $i, $Piece, 0, $Count)
            $null = Unprotect-CIPPCloudBackupStreamBlock -Decryptor $Decryptor -Buffer $Piece -OutputStream $Out
        }
        $null = Unprotect-CIPPCloudBackupStreamBlock -Decryptor $Decryptor -Buffer ([byte[]]::new(0)) -OutputStream $Out -Final
        $Out.Position = 0
        [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Out)) | Should -Be (Get-PatternHash (64KB * 3))
        $Decryptor.DataKey | Should -Be ([byte[]]::new(32))
    }

    It 'throws when the stream ends before its last chunk, or carries data after it' {
        $Cipher = [System.IO.MemoryStream]::new()
        $null = Protect-CIPPCloudBackupStream -InputStream ([CippTestRestorePattern]::new(64KB * 2)) -OutputStream $Cipher -KeyId $EncKeyId -Key $EncKey -ChunkSize 64KB
        $Data = $Cipher.ToArray()
        $Truncated = [byte[]]::new(100 + (64KB + 16) * 2)
        [System.Array]::Copy($Data, $Truncated, $Truncated.Length)
        { Unprotect-CIPPCloudBackupStreamBlock -Decryptor @{} -Buffer $Truncated -OutputStream ([System.IO.MemoryStream]::new()) -Final } | Should -Throw '*incomplete*'

        $Decryptor = @{}
        $null = Unprotect-CIPPCloudBackupStreamBlock -Decryptor $Decryptor -Buffer $Data -OutputStream ([System.IO.MemoryStream]::new()) -Final
        { Unprotect-CIPPCloudBackupStreamBlock -Decryptor $Decryptor -Buffer ([byte[]](1)) -OutputStream ([System.IO.MemoryStream]::new()) } | Should -Throw '*changed or is damaged*'
    }
}
