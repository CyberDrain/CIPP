BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup'
    Add-Type -Path (Join-Path $BackendRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    function Get-CIPPClientCredentialToken { param($TenantId, $ClientId, $ClientSecret, $Scope) }
    function Get-CIPPCloudBackupKey { param($KeyId) }
    foreach ($File in Get-ChildItem $Folder -Filter '*.ps1') {
        if ($File.BaseName -match '(Azure|S3)(Object|ObjectList|ObjectStream|ObjectVersionList)$|^(Invoke-CIPPCloudBackupAzureBlobRequest|Invoke-CIPPS3Request|Get-CIPPS3Signature|Read-CIPPCloudBackupStreamBlock|Protect-CIPPCloudBackupStream|Unprotect-CIPPCloudBackupStream|Unprotect-CIPPCloudBackupStreamBlock|Send-CIPPCloudBackupObjectStream|Receive-CIPPCloudBackupObjectStream|Get-CIPPCloudBackupObjectVersionList|Get-CIPPCloudBackupObjectList|Get-CIPPCloudBackupObject|Set-CIPPCloudBackupObject|Remove-CIPPCloudBackupObject)$') {
            . $File.FullName
        }
    }

    if (-not ('CippTestCountingStream' -as [type])) {
        Add-Type -TypeDefinition @'
public sealed class CippTestCountingStream : System.IO.Stream
{
    private readonly long _length;
    private long _position;
    public CippTestCountingStream(long length) { _length = length; }
    public static byte ValueAt(long position) { return (byte)((position * 31 + 7) % 251); }
    public override int Read(byte[] buffer, int offset, int count)
    {
        int n = (int)System.Math.Min(count, _length - _position);
        for (int i = 0; i < n; i++) { buffer[offset + i] = ValueAt(_position + i); }
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

    function Get-SourceHash {
        param([long]$Length)
        $Source = [CippTestCountingStream]::new($Length)
        [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Source))
    }

    $script:AzureDestination = [pscustomobject]@{
        Provider = 'AzureBlob'; StorageAccount = 'cippbackup'; Container = 'backups'; SubscriptionId = '22222222-2222-2222-2222-222222222222'
        ResourceGroup = 'rg-backup'; AzureTenantId = 'contoso.onmicrosoft.com'; ClientId = 'app-id'; Secret = 'app-secret'
    }
    $script:S3Destination = [pscustomobject]@{ Provider = 'S3'; Bucket = 'my-bucket'; Region = 'us-east-1'; AccessKeyId = 'AKIDTEST'; Secret = 'secret/key+value'; Endpoint = ''; ForcePathStyle = $false }
    $script:EncKeyId = [guid]::NewGuid().ToString()
    $script:EncKey = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
}

Describe 'Send-CIPPCloudBackupObjectStream' {
    BeforeEach {
        Mock Set-CIPPCloudBackupAzureObject { [pscustomobject]@{ Key = $Key; Bytes = [int64]$Body.Length; VersionId = 'v-single' } }
        Mock Set-CIPPCloudBackupS3Object { [pscustomobject]@{ Key = $Key; Bytes = [int64]$Body.Length; VersionId = $null } }
        Mock Send-CIPPCloudBackupAzureObjectStream { [pscustomobject]@{ Key = $Key; Bytes = 1; VersionId = 'v-blocks' } }
        Mock Send-CIPPCloudBackupS3ObjectStream { [pscustomobject]@{ Key = $Key; Bytes = 1; VersionId = 'v-parts' } }
    }

    It 'sends a stream under 8 MiB with one PUT and returns its key, size and version' {
        $Result = Send-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key 'p/c/onedrive/u/items/d/i' -Stream ([CippTestCountingStream]::new(1000)) -ContentType 'text/plain' -Metadata @{ A = 'b' }
        $Result.Key | Should -Be 'p/c/onedrive/u/items/d/i'
        $Result.Bytes | Should -Be 1000
        $Result.VersionId | Should -Be 'v-single'
        Should -Invoke Set-CIPPCloudBackupAzureObject -Times 1 -Exactly -ParameterFilter { $Body.Length -eq 1000 -and $ContentType -eq 'text/plain' -and $Metadata.A -eq 'b' }
        Should -Invoke Send-CIPPCloudBackupAzureObjectStream -Times 0 -Exactly
    }

    It 'sends an empty stream as an empty object' {
        $Result = Send-CIPPCloudBackupObjectStream -Destination $S3Destination -Key 'k' -Stream ([System.IO.MemoryStream]::new())
        $Result.Bytes | Should -Be 0
        $Result.VersionId | Should -BeNullOrEmpty
        Should -Invoke Set-CIPPCloudBackupS3Object -Times 1 -Exactly -ParameterFilter { $Body.Length -eq 0 -and $ContentType -eq 'application/octet-stream' }
    }

    It 'hands a stream of 8 MiB or more to the <Provider> chunked upload with the first block read' -ForEach @(
        @{ Provider = 'AzureBlob'; Target = 'Send-CIPPCloudBackupAzureObjectStream'; Expected = 'v-blocks' }
        @{ Provider = 'S3'; Target = 'Send-CIPPCloudBackupS3ObjectStream'; Expected = 'v-parts' }
    ) {
        $Destination = if ($Provider -eq 'S3') { $S3Destination } else { $AzureDestination }
        $Source = [CippTestCountingStream]::new(8MB)
        (Send-CIPPCloudBackupObjectStream -Destination $Destination -Key 'k' -Stream $Source).VersionId | Should -Be $Expected
        Should -Invoke $Target -Times 1 -Exactly -ParameterFilter { $FirstBlock.Length -eq 8MB -and $Reader.Stream -eq $Source -and $Key -eq 'k' }
        $Source.Position | Should -Be 8MB
    }

    It 'encrypts a small stream as CIPPENC2 before the single PUT' {
        Mock Get-CIPPCloudBackupKey { , ([byte[]]$script:EncKey.Clone()) }
        $script:Sent = $null
        Mock Set-CIPPCloudBackupAzureObject { $script:Sent = $Body; [pscustomobject]@{ Key = $Key; Bytes = [int64]$Body.Length; VersionId = $null } }
        $Plain = [byte[]](1..200)
        $Result = Send-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key 'k.enc' -Stream ([System.IO.MemoryStream]::new($Plain)) -KeyId $EncKeyId -EncryptionKey $EncKey
        $Result.Bytes | Should -Be (100 + 200 + 16)
        $Result.Size | Should -Be 200
        [System.Text.Encoding]::ASCII.GetString($Sent, 0, 8) | Should -Be 'CIPPENC2'
        $Out = [System.IO.MemoryStream]::new()
        $null = Unprotect-CIPPCloudBackupStream -InputStream ([System.IO.MemoryStream]::new($Sent)) -OutputStream $Out
        ($Out.ToArray() -join ',') | Should -Be ($Plain -join ',')
    }

    It 'rejects a key id without a key, and an unknown provider' {
        { Send-CIPPCloudBackupObjectStream -Destination $S3Destination -Key 'k' -Stream ([System.IO.MemoryStream]::new()) -KeyId $EncKeyId } | Should -Throw -ExceptionType ([System.ArgumentException])
        { Send-CIPPCloudBackupObjectStream -Destination ([pscustomobject]@{ Provider = 'Dropbox' }) -Key 'k' -Stream ([System.IO.MemoryStream]::new()) } | Should -Throw -ExceptionType ([System.ArgumentException])
    }
}

Describe 'Azure block upload' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $script:Source = $null
        Mock Invoke-CIPPCloudBackupAzureBlobRequest {
            $Copy = if ($Body) { [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Body)) }
            $script:Calls.Add([pscustomobject]@{ Method = $Method; Key = $Key; Query = $Query; Headers = $Headers; Length = $Body.Length; Body = $(if ($Query.comp -eq 'blocklist') { [System.Text.Encoding]::UTF8.GetString($Body) }); Hash = $Copy; ContentType = $ContentType; Position = $script:Source.Position })
            @{ StatusCode = 201; Headers = @{ 'x-ms-version-id' = @('2026-11-20T10:00:00.0000000Z') }; Body = [byte[]]::new(0) }
        }
    }

    It 'uploads <Name> in bounded blocks and commits them in order' -ForEach @(
        @{ Name = 'a 20 MiB stream'; Length = 20MB + 5 }
        @{ Name = 'exactly 16 MiB'; Length = 16MB }
    ) {
        $script:Source = [CippTestCountingStream]::new($Length)
        $Result = Send-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key 'p/c/sharepoint/host,site,web/items/d/i' -Stream $Source -ContentType 'application/pdf' -Metadata @{ Sha = 'x' }
        $Result.Bytes | Should -Be $Length
        $Result.VersionId | Should -Be '2026-11-20T10:00:00.0000000Z'

        $Blocks = @($Calls.Where({ $_.Query.comp -eq 'block' }))
        $Blocks.Count | Should -Be ([Math]::Ceiling($Length / 8MB))
        $Uploaded = 0
        foreach ($Block in $Blocks) {
            $Block.Length | Should -BeLessOrEqual 8MB
            $Uploaded += $Block.Length
            $Block.Position | Should -Be $Uploaded
        }
        $Uploaded | Should -Be $Length
        @($Blocks.Query.blockid | ForEach-Object Length | Select-Object -Unique).Count | Should -Be 1
        @($Blocks.Query.blockid | Select-Object -Unique).Count | Should -Be $Blocks.Count

        $Commit = $Calls[$Calls.Count - 1]
        $Commit.Query.comp | Should -Be 'blocklist'
        $Commit.ContentType | Should -Be 'application/xml'
        $Commit.Headers['x-ms-blob-content-type'] | Should -Be 'application/pdf'
        $Commit.Headers['x-ms-meta-Sha'] | Should -Be 'x'
        @(([xml]$Commit.Body).BlockList.Latest) | Should -Be @($Blocks.Query.blockid)
    }

    It 'keeps encryption read-ahead within one chunk while streaming' {
        $script:Source = [CippTestCountingStream]::new(20MB)
        $Result = Send-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key 'k' -Stream $Source -KeyId $EncKeyId -EncryptionKey $EncKey
        $Frames = [Math]::Floor(20MB / 4MB) + 1
        $Result.Bytes | Should -Be (100 + 20MB + 16 * $Frames)
        $Result.Size | Should -Be 20MB
        $Uploaded = 0
        foreach ($Block in $Calls.Where({ $_.Query.comp -eq 'block' })) {
            $Uploaded += $Block.Length
            ($Block.Position - $Uploaded) | Should -BeLessOrEqual 4MB
        }
    }

    It 'rejects metadata names Azure does not accept before uploading' {
        $script:Source = [CippTestCountingStream]::new(9MB)
        { Send-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key 'k' -Stream $Source -Metadata @{ 'bad-name' = 'x' } } | Should -Throw -ExceptionType ([System.ArgumentException])
        $Calls.Count | Should -Be 0
    }
}

Describe 'S3 multipart upload' {
    BeforeEach {
        $script:Calls = [System.Collections.Generic.List[object]]::new()
        $script:Source = $null
        $script:CompleteBody = '<CompleteMultipartUploadResult><Key>k</Key><ETag>"x-3"</ETag></CompleteMultipartUploadResult>'
        $script:FailPart = 0
        Mock Invoke-CIPPS3Request {
            $script:Calls.Add([pscustomobject]@{ Method = $Method; Key = $Key; Query = $Query; Headers = $Headers; Size = $Body.Length; Text = $(if ($Method -eq 'POST' -and $Body) { [System.Text.Encoding]::UTF8.GetString($Body) }); Position = $script:Source.Position })
            if ($Method -eq 'POST' -and $Query.ContainsKey('uploads')) {
                return [pscustomobject]@{ StatusCode = 200; Headers = @{}; Body = [System.Text.Encoding]::UTF8.GetBytes('<?xml version="1.0" encoding="UTF-8"?><InitiateMultipartUploadResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Bucket>my-bucket</Bucket><Key>k</Key><UploadId>up/1+=</UploadId></InitiateMultipartUploadResult>') }
            }
            if ($Method -eq 'PUT') {
                if ([int]$Query.partNumber -eq $script:FailPart) { throw 'S3 PUT failed with AccessDenied' }
                return [pscustomobject]@{ StatusCode = 200; Headers = @{ ETag = "`"etag-$($Query.partNumber)`"" }; Body = [byte[]]::new(0) }
            }
            if ($Method -eq 'POST') {
                return [pscustomobject]@{ StatusCode = 200; Headers = @{ 'x-amz-version-id' = 'ver-1' }; Body = [System.Text.Encoding]::UTF8.GetBytes($script:CompleteBody) }
            }
            [pscustomobject]@{ StatusCode = 204; Headers = @{}; Body = [byte[]]::new(0) }
        }
    }

    It 'creates the upload, sends bounded parts and completes with every part and ETag' {
        $script:Source = [CippTestCountingStream]::new(20MB + 1)
        $Result = Send-CIPPCloudBackupObjectStream -Destination $S3Destination -Key 'p/k' -Stream $Source -ContentType 'message/rfc822' -Metadata @{ Hash = 'abc' }
        $Result.Bytes | Should -Be (20MB + 1)
        $Result.VersionId | Should -Be 'ver-1'

        $Calls[0].Method | Should -Be 'POST'
        $Calls[0].Query.ContainsKey('uploads') | Should -BeTrue
        $Calls[0].Headers['Content-Type'] | Should -Be 'message/rfc822'
        $Calls[0].Headers['x-amz-meta-Hash'] | Should -Be 'abc'

        $Parts = @($Calls.Where({ $_.Method -eq 'PUT' }))
        $Parts.Query.partNumber | Should -Be @('1', '2', '3')
        $Parts.Query.uploadId | Select-Object -Unique | Should -Be 'up/1+='
        $Parts.Size | Should -Be @(8MB, 8MB, (4MB + 1))
        $Uploaded = 0
        foreach ($Part in $Parts) { $Uploaded += $Part.Size; $Part.Position | Should -Be $Uploaded }

        $Complete = $Calls[$Calls.Count - 1]
        $Complete.Method | Should -Be 'POST'
        $Complete.Query.uploadId | Should -Be 'up/1+='
        $Complete.Headers['Content-Type'] | Should -Be 'application/xml'
        $Xml = [xml]$Complete.Text
        @($Xml.CompleteMultipartUpload.Part.PartNumber) | Should -Be @('1', '2', '3')
        @($Xml.CompleteMultipartUpload.Part.ETag) | Should -Be @('"etag-1"', '"etag-2"', '"etag-3"')
        Should -Invoke Invoke-CIPPS3Request -Times 0 -Exactly -ParameterFilter { $Method -eq 'DELETE' }
    }

    It 'aborts the upload when a part fails' {
        $script:FailPart = 2
        $script:Source = [CippTestCountingStream]::new(17MB)
        { Send-CIPPCloudBackupObjectStream -Destination $S3Destination -Key 'p/k' -Stream $Source } | Should -Throw '*AccessDenied*'
        Should -Invoke Invoke-CIPPS3Request -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Query.uploadId -eq 'up/1+=' -and $Key -eq 'p/k' }
        Should -Invoke Invoke-CIPPS3Request -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' -and $Query.ContainsKey('uploadId') }
    }

    It 'aborts and throws when the completion returns an error document with HTTP 200' {
        $script:CompleteBody = '<?xml version="1.0" encoding="UTF-8"?><Error><Code>InternalError</Code><Message>We encountered an internal error.</Message></Error>'
        $script:Source = [CippTestCountingStream]::new(8MB)
        { Send-CIPPCloudBackupObjectStream -Destination $S3Destination -Key 'p/k' -Stream $Source } | Should -Throw '*InternalError*'
        Should -Invoke Invoke-CIPPS3Request -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Query.uploadId -eq 'up/1+=' }
    }

    It 'grows the part size after 1,000 parts' {
        Mock Read-CIPPCloudBackupStreamBlock { $script:Requested.Add($Size); if ($script:Requested.Count -lt 1001) { , [byte[]]::new($Size) } else { , [byte[]]::new(3) } }
        $script:Requested = [System.Collections.Generic.List[int]]::new()
        $script:Source = [System.IO.MemoryStream]::new()
        $null = Send-CIPPCloudBackupS3ObjectStream -Destination $S3Destination -Key 'k' -Reader @{ Stream = $Source } -FirstBlock ([byte[]]::new(8MB))
        $Requested[998] | Should -Be 8MB
        $Requested[999] | Should -Be 16MB
        @($Calls.Where({ $_.Method -eq 'PUT' })).Count | Should -Be 1002
    }
}

Describe 'Version listing' {
    It 'lists Azure blob versions across pages with current flags' {
        $script:Page = 0
        Mock Invoke-CIPPCloudBackupAzureBlobRequest {
            $script:Page++
            $Xml = if ($script:Page -eq 1) {
                '<?xml version="1.0" encoding="utf-8"?><EnumerationResults><Blobs><Blob><Name>p/a</Name><VersionId>2026-11-01T00:00:00.0000000Z</VersionId><Properties><Last-Modified>Sun, 01 Nov 2026 00:00:00 GMT</Last-Modified><Content-Length>5</Content-Length></Properties></Blob><Blob><Name>p/a</Name><VersionId>2026-11-02T00:00:00.0000000Z</VersionId><IsCurrentVersion>true</IsCurrentVersion><Properties><Last-Modified>Mon, 02 Nov 2026 00:00:00 GMT</Last-Modified><Content-Length>7</Content-Length></Properties></Blob></Blobs><NextMarker>m1</NextMarker></EnumerationResults>'
            } else {
                '<?xml version="1.0" encoding="utf-8"?><EnumerationResults><Blobs><Blob><Name>p/deleted</Name><VersionId>2026-10-01T00:00:00.0000000Z</VersionId><Properties><Last-Modified>Thu, 01 Oct 2026 00:00:00 GMT</Last-Modified><Content-Length>9</Content-Length></Properties></Blob><Blob><Name>p/old</Name><Properties><Last-Modified>Thu, 01 Oct 2026 00:00:00 GMT</Last-Modified><Content-Length>1</Content-Length></Properties></Blob></Blobs><NextMarker /></EnumerationResults>'
            }
            @{ StatusCode = 200; Headers = @{}; Body = [System.Text.Encoding]::UTF8.GetBytes($Xml) }
        }
        $Versions = @(Get-CIPPCloudBackupObjectVersionList -Destination $AzureDestination -Prefix 'p/')
        $Versions.Key | Should -Be @('p/a', 'p/a', 'p/deleted', 'p/old')
        $Versions.IsLatest | Should -Be @($false, $true, $false, $true)
        $Versions.IsDeleteMarker | Should -Be @($false, $false, $false, $false)
        $Versions[1].VersionId | Should -Be '2026-11-02T00:00:00.0000000Z'
        $Versions[3].VersionId | Should -BeNullOrEmpty
        $Versions[1].Size | Should -Be 7
        $Versions[1].LastModified.Kind | Should -Be 'Utc'
        Should -Invoke Invoke-CIPPCloudBackupAzureBlobRequest -Times 1 -Exactly -ParameterFilter { $Query.include -eq 'versions,metadata' -and $Query.prefix -eq 'p/' -and -not $Query.marker }
        Should -Invoke Invoke-CIPPCloudBackupAzureBlobRequest -Times 1 -Exactly -ParameterFilter { $Query.marker -eq 'm1' }
    }

    It 'lists S3 versions and delete markers in order across pages' {
        $Ns = 'http://s3.amazonaws.com/doc/2006-03-01/'
        Mock Invoke-CIPPS3Request {
            [pscustomobject]@{ StatusCode = 200; Headers = @{}; Body = [byte[]]::new(0); Xml = [xml]"<ListVersionsResult xmlns='$Ns'><IsTruncated>true</IsTruncated><NextKeyMarker>p/b</NextKeyMarker><NextVersionIdMarker>v/2</NextVersionIdMarker><Version><Key>p/a</Key><VersionId>v1</VersionId><IsLatest>true</IsLatest><LastModified>2026-11-01T10:00:00.000Z</LastModified><Size>10</Size></Version><DeleteMarker><Key>p/b</Key><VersionId>v/2</VersionId><IsLatest>true</IsLatest><LastModified>2026-11-02T10:00:00.000Z</LastModified></DeleteMarker></ListVersionsResult>" }
        } -ParameterFilter { -not $Query['key-marker'] }
        Mock Invoke-CIPPS3Request {
            [pscustomobject]@{ StatusCode = 200; Headers = @{}; Body = [byte[]]::new(0); Xml = [xml]"<ListVersionsResult xmlns='$Ns'><IsTruncated>false</IsTruncated><Version><Key>p/b</Key><VersionId>null</VersionId><IsLatest>false</IsLatest><LastModified>2026-10-01T10:00:00.000Z</LastModified><Size>5000000000</Size></Version></ListVersionsResult>" }
        } -ParameterFilter { $Query['key-marker'] -eq 'p/b' -and $Query['version-id-marker'] -eq 'v/2' }

        $Versions = @(Get-CIPPCloudBackupObjectVersionList -Destination $S3Destination -Prefix 'p/')
        $Versions.Key | Should -Be @('p/a', 'p/b', 'p/b')
        $Versions.VersionId | Should -Be @('v1', 'v/2', 'null')
        $Versions.IsDeleteMarker | Should -Be @($false, $true, $false)
        $Versions.IsLatest | Should -Be @($true, $true, $false)
        $Versions[1].Size | Should -Be 0
        $Versions[2].Size | Should -Be 5000000000
        $Versions[0].LastModified | Should -Be ([datetime]::new(2026, 11, 1, 10, 0, 0, [System.DateTimeKind]::Utc))
        Should -Invoke Invoke-CIPPS3Request -Times 2 -Exactly -ParameterFilter { $Query.ContainsKey('versions') -and $Query.prefix -eq 'p/' -and $Method -eq 'GET' -and -not $Key }
    }
}

Describe 'Versioned reads and deletes' {
    It 'reads one Azure version by id' {
        Mock Invoke-CIPPCloudBackupAzureBlobRequest { @{ StatusCode = 200; Headers = @{ 'x-ms-version-id' = @('v1') }; Body = [byte[]](1, 2) } }
        $Object = Get-CIPPCloudBackupObject -Destination $AzureDestination -Key 'p/a' -VersionId 'v1'
        $Object.VersionId | Should -Be 'v1'
        ($Object.Body -join ',') | Should -Be '1,2'
        Should -Invoke Invoke-CIPPCloudBackupAzureBlobRequest -ParameterFilter { $Method -eq 'GET' -and $Query.versionid -eq 'v1' }
    }

    It 'reads one S3 version by id' {
        Mock Invoke-CIPPS3Request { [pscustomobject]@{ StatusCode = 200; Headers = @{ 'x-amz-version-id' = 'v1' }; Body = [byte[]](3); Xml = $null } }
        (Get-CIPPCloudBackupObject -Destination $S3Destination -Key 'p/a' -VersionId 'v1').VersionId | Should -Be 'v1'
        Should -Invoke Invoke-CIPPS3Request -ParameterFilter { $Method -eq 'GET' -and $Query.versionId -eq 'v1' }
    }

    It 'deletes without a version id so a versioned <Provider> destination keeps the data' -ForEach @(
        @{ Provider = 'AzureBlob' }, @{ Provider = 'S3' }
    ) {
        Mock Invoke-CIPPCloudBackupAzureBlobRequest { @{ StatusCode = 202; Headers = @{}; Body = [byte[]]::new(0) } }
        Mock Invoke-CIPPS3Request { [pscustomobject]@{ StatusCode = 204; Headers = @{ 'x-amz-delete-marker' = 'true' }; Body = [byte[]]::new(0) } }
        $Destination = if ($Provider -eq 'S3') { $S3Destination } else { $AzureDestination }
        Remove-CIPPCloudBackupObject -Destination $Destination -Key 'p/a'
        if ($Provider -eq 'S3') {
            Should -Invoke Invoke-CIPPS3Request -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Key -eq 'p/a' -and $Query.Count -eq 0 }
        } else {
            Should -Invoke Invoke-CIPPCloudBackupAzureBlobRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'DELETE' -and $Key -eq 'p/a' -and -not $Query }
        }
    }

    It 'treats deleting a key that was never written as done on S3 (<Code>)' -ForEach @(@{ Code = 'NoSuchKey' }, @{ Code = 'NotFound' }) {
        Mock Invoke-CIPPS3Request { $E = [System.Exception]::new("S3 DELETE failed with $Code"); $E.Data['S3ErrorCode'] = $Code; throw $E }
        { Remove-CIPPCloudBackupObject -Destination $S3Destination -Key 'never/written' } | Should -Not -Throw
    }

    It 'still throws other S3 delete failures' {
        Mock Invoke-CIPPS3Request { $E = [System.Exception]::new('S3 DELETE failed with AccessDenied'); $E.Data['S3ErrorCode'] = 'AccessDenied'; throw $E }
        { Remove-CIPPCloudBackupObject -Destination $S3Destination -Key 'k' } | Should -Throw '*AccessDenied*'
    }
}

Describe 'Azure streaming over HTTP' {
    BeforeAll {
        $script:RealInvokeWebRequest = Get-Command -Name 'Invoke-WebRequest' -CommandType Cmdlet
        $Probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $Probe.Start()
        $script:AzurePort = $Probe.LocalEndpoint.Port
        $Probe.Stop()
        $script:AzureListener = [System.Net.HttpListener]::new()
        $AzureListener.Prefixes.Add("http://127.0.0.1:$AzurePort/")
        $AzureListener.Start()
        $script:AzureLog = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $script:AzureServer = [powershell]::Create()
        $null = $AzureServer.AddScript({
                param($Listener, $Log)
                $Blobs = @{}
                $Blocks = @{}
                $Counter = 0
                while ($Listener.IsListening) {
                    try { $Context = $Listener.GetContext() } catch { break }
                    $Request = $Context.Request
                    $Response = $Context.Response
                    $Buffer = [System.IO.MemoryStream]::new()
                    $Request.InputStream.CopyTo($Buffer)
                    $Body = $Buffer.ToArray()
                    $Path = [uri]::UnescapeDataString($Request.Url.AbsolutePath)
                    $Comp = $Request.QueryString['comp']
                    $Log.Enqueue([pscustomobject]@{ Method = $Request.HttpMethod; RawUrl = $Request.RawUrl; Comp = $Comp; BlockId = $Request.QueryString['blockid']; Length = $Body.Length; Range = $Request.Headers['x-ms-range']; IfMatch = $Request.Headers['If-Match'] })
                    if ($Request.HttpMethod -eq 'PUT' -and $Comp -eq 'metadata') {
                        if ($Blobs[$Path]) {
                            $Counter++
                            $Blobs[$Path].Version = "v$Counter"
                            $Blobs[$Path].Meta = @{ 'x-ms-meta-cippdeletedat' = $Request.Headers['x-ms-meta-cippdeletedat'] }
                        } else {
                            $Response.StatusCode = 404
                            $Response.AddHeader('x-ms-error-code', 'BlobNotFound')
                        }
                    } elseif ($Request.HttpMethod -eq 'PUT' -and $Comp -eq 'block') {
                        $Blocks[$Request.QueryString['blockid']] = $Body
                        $Response.StatusCode = 201
                    } elseif ($Request.HttpMethod -eq 'PUT') {
                        if ($Comp -eq 'blocklist') {
                            $Data = [System.IO.MemoryStream]::new()
                            foreach ($Id in ([xml][System.Text.Encoding]::UTF8.GetString($Body)).BlockList.Latest) { $Part = $Blocks[$Id]; $Data.Write($Part, 0, $Part.Length) }
                            $Data = $Data.ToArray()
                            $Type = $Request.Headers['x-ms-blob-content-type']
                        } else {
                            $Data = $Body
                            $Type = $Request.ContentType
                        }
                        $Counter++
                        $Meta = @{}
                        foreach ($Name in $Request.Headers.AllKeys) { if ($Name -like 'x-ms-meta-*') { $Meta[$Name] = $Request.Headers[$Name] } }
                        $Blobs[$Path] = @{ Data = $Data; Version = "v$Counter"; ETag = "`"etag$Counter`""; Type = $Type; Meta = $Meta }
                        $Response.StatusCode = 201
                        $Response.AddHeader('x-ms-version-id', "v$Counter")
                    } elseif ($Comp -eq 'list') {
                        $Prefix = '/backups/' + $Request.QueryString['prefix']
                        $Xml = [System.Text.StringBuilder]::new('<?xml version="1.0" encoding="utf-8"?><EnumerationResults><Blobs>')
                        foreach ($Name in @($Blobs.Keys | Sort-Object)) {
                            if (-not $Name.StartsWith($Prefix)) { continue }
                            $null = $Xml.Append('<Blob><Name>').Append([System.Security.SecurityElement]::Escape($Name.Substring(9))).Append('</Name><Properties><Last-Modified>Fri, 20 Nov 2026 10:00:00 GMT</Last-Modified><Content-Length>').Append($Blobs[$Name].Data.Length).Append('</Content-Length></Properties></Blob>')
                        }
                        $null = $Xml.Append('</Blobs><NextMarker /></EnumerationResults>')
                        $Reply = [System.Text.Encoding]::UTF8.GetBytes($Xml.ToString())
                        $Response.OutputStream.Write($Reply, 0, $Reply.Length)
                    } else {
                        $Blob = $Blobs[$Path]
                        if (-not $Blob) {
                            $Response.StatusCode = 404
                            $Response.AddHeader('x-ms-error-code', 'BlobNotFound')
                        } elseif ($Request.HttpMethod -eq 'DELETE') {
                            $Blobs.Remove($Path)
                            $Response.StatusCode = 202
                        } elseif ($Request.HttpMethod -eq 'GET' -and -not $Request.Headers['x-ms-range']) {
                            $Response.AddHeader('x-ms-version-id', $Blob.Version)
                            foreach ($Name in $Blob.Meta.Keys) { $Response.AddHeader($Name, $Blob.Meta[$Name]) }
                            $Response.OutputStream.Write($Blob.Data, 0, $Blob.Data.Length)
                        } elseif ($Request.HttpMethod -eq 'HEAD') {
                            $Response.ContentLength64 = $Blob.Data.Length
                            $Response.ContentType = $Blob.Type
                            $Response.AddHeader('ETag', $Blob.ETag)
                            $Response.AddHeader('x-ms-version-id', $Blob.Version)
                            foreach ($Name in $Blob.Meta.Keys) { $Response.AddHeader($Name, $Blob.Meta[$Name]) }
                        } elseif ($Request.Headers['If-Match'] -ne $Blob.ETag) {
                            $Response.StatusCode = 412
                        } else {
                            $Range = $Request.Headers['x-ms-range'] -replace '^bytes=', ''
                            $Start = [int64]$Range.Split('-')[0]
                            $End = [int64]$Range.Split('-')[1]
                            $Response.StatusCode = 206
                            $Response.ContentType = 'text/plain; charset=utf-8'
                            $Response.OutputStream.Write($Blob.Data, $Start, $End - $Start + 1)
                        }
                    }
                    $Response.Close()
                }
            }).AddArgument($AzureListener).AddArgument($AzureLog)
        $script:AzureHandle = $AzureServer.BeginInvoke()
    }

    AfterAll {
        $AzureListener.Stop()
        $AzureListener.Close()
        $AzureServer.Dispose()
    }

    BeforeEach {
        Mock Get-CIPPClientCredentialToken { 'token' }
        Mock Get-CIPPCloudBackupKey { , ([byte[]]$script:EncKey.Clone()) }
        Mock Invoke-WebRequest {
            $Local = @{} + $PesterBoundParameters
            $Local.Uri = ([string]$Uri).Replace('https://cippbackup.blob.core.windows.net', "http://127.0.0.1:$script:AzurePort")
            & $script:RealInvokeWebRequest @Local
        }
        $Item = $null
        while ($AzureLog.TryDequeue([ref]$Item)) { }
    }

    It 'round-trips an encrypted 17 MiB stream through blocks and ranged reads under a key with commas' {
        $Key = 'p/c/sharepoint/contoso.sharepoint.com,1111,2222/items/drive/item'
        $Sent = Send-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key $Key -Stream ([CippTestCountingStream]::new(17MB)) -Metadata @{ Kind = 'file' } -KeyId $EncKeyId -EncryptionKey $EncKey
        $Sent.VersionId | Should -Be 'v1'

        $Log = @($AzureLog.ToArray())
        $Log[0].RawUrl | Should -BeLike '/backups/p/c/sharepoint/contoso.sharepoint.com%2C1111%2C2222/items/drive/item?comp=block&blockid=*'
        @($Log.Where({ $_.Comp -eq 'block' })).Count | Should -Be 3
        $Log[$Log.Count - 1].Comp | Should -Be 'blocklist'

        $Encrypted = [System.IO.MemoryStream]::new()
        $Received = Receive-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key $Key -OutStream $Encrypted
        $Received.Bytes | Should -Be $Sent.Bytes
        $Received.VersionId | Should -Be 'v1'
        $Received.Metadata.Kind | Should -Be 'file'
        $Ranges = @($AzureLog.ToArray().Where({ $_.Method -eq 'GET' }))
        $Ranges.Range | Should -Be @('bytes=0-8388607', 'bytes=8388608-16777215', "bytes=16777216-$($Sent.Bytes - 1)")
        $Ranges.IfMatch | Should -Be @('"etag1"', '"etag1"', '"etag1"')

        $Encrypted.Position = 0
        $Plain = [System.IO.MemoryStream]::new()
        $null = Unprotect-CIPPCloudBackupStream -InputStream $Encrypted -OutputStream $Plain
        $Plain.Position = 0
        [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Plain)) | Should -Be (Get-SourceHash 17MB)
    }

    It 'reads only the requested range and still reports the full size' {
        $null = Send-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key 'ranged' -Stream ([CippTestCountingStream]::new(20MB))
        $Item = $null
        while ($AzureLog.TryDequeue([ref]$Item)) { }
        $Out = [System.IO.MemoryStream]::new()
        $Received = Receive-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key 'ranged' -Offset 9MB -Length 9MB -OutStream $Out
        $Received.Bytes | Should -Be 20MB
        $Out.Length | Should -Be 9MB
        $Out.ToArray()[0] | Should -Be ([CippTestCountingStream]::ValueAt(9MB))
        @($AzureLog.ToArray().Where({ $_.Method -eq 'GET' })).Range | Should -Be @("bytes=$(9MB)-$(17MB - 1)", "bytes=$(17MB)-$(18MB - 1)")
        $Tail = [System.IO.MemoryStream]::new()
        $null = Receive-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key 'ranged' -Offset 19MB -Length 8MB -OutStream $Tail
        $Tail.Length | Should -Be 1MB
    }

    It 'puts, gets, lists and removes a key with <Name>' -ForEach @(
        @{ Name = 'commas'; Key = 'p/c/sharepoint/contoso.sharepoint.com,1111,2222/items/d/i' }
        @{ Name = 'a Teams thread id'; Key = 'p/c/teams/u/items/19:abc123@thread.v2/1700000000000.json' }
        @{ Name = 'spaces and a plus'; Key = 'p/c/x/items/a b+c/d e.json' }
    ) {
        $Put = Set-CIPPCloudBackupObject -Destination $AzureDestination -Key $Key -Body ([byte[]](1, 2, 3)) -Metadata @{ Kind = 'x' }
        $Put.Key | Should -BeExactly $Key
        $Put.Bytes | Should -Be 3
        $Got = Get-CIPPCloudBackupObject -Destination $AzureDestination -Key $Key
        ($Got.Body -join ',') | Should -Be '1,2,3'
        $Got.VersionId | Should -Be $Put.VersionId
        @(Get-CIPPCloudBackupObjectList -Destination $AzureDestination -Prefix ($Key.Substring(0, $Key.LastIndexOf('/') + 1))).Key | Should -Be @($Key)
        Remove-CIPPCloudBackupObject -Destination $AzureDestination -Key $Key
        Get-CIPPCloudBackupObject -Destination $AzureDestination -Key $Key | Should -BeNullOrEmpty
        { Remove-CIPPCloudBackupObject -Destination $AzureDestination -Key $Key } | Should -Not -Throw
    }

    It 'reads a small object, an empty object and returns $null for a missing one' {
        $null = Send-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key 'small' -Stream ([System.IO.MemoryStream]::new([byte[]](0..255))) -ContentType 'application/x-test'
        $null = Send-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key 'empty' -Stream ([System.IO.MemoryStream]::new())
        $Out = [System.IO.MemoryStream]::new()
        $Small = Receive-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key 'small' -OutStream $Out
        ($Out.ToArray() -join ',') | Should -Be ((0..255) -join ',')
        $Small.ContentType | Should -Be 'application/x-test'
        $Empty = [System.IO.MemoryStream]::new()
        (Receive-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key 'empty' -OutStream $Empty).Bytes | Should -Be 0
        $Empty.Length | Should -Be 0
        Receive-CIPPCloudBackupObjectStream -Destination $AzureDestination -Key 'missing' -OutStream $Empty | Should -BeNullOrEmpty
    }
}

Describe 'S3 streaming over HTTP' {
    BeforeAll {
        $Probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $Probe.Start()
        $script:S3Port = $Probe.LocalEndpoint.Port
        $Probe.Stop()
        $script:S3Listener = [System.Net.HttpListener]::new()
        $S3Listener.Prefixes.Add("http://127.0.0.1:$S3Port/")
        $S3Listener.Start()
        $script:S3Log = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $script:S3Control = [hashtable]::Synchronized(@{ FailPart = 0 })
        $script:S3Server = [powershell]::Create()
        $null = $S3Server.AddScript({
                param($Listener, $Log, $Control)
                $Objects = @{}
                $Uploads = @{}
                $Counter = 0
                while ($Listener.IsListening) {
                    try { $Context = $Listener.GetContext() } catch { break }
                    $Request = $Context.Request
                    $Response = $Context.Response
                    $Buffer = [System.IO.MemoryStream]::new()
                    $Request.InputStream.CopyTo($Buffer)
                    $Body = $Buffer.ToArray()
                    $Headers = @{}
                    foreach ($Name in $Request.Headers.AllKeys) { $Headers[$Name] = $Request.Headers[$Name] }
                    $Log.Enqueue([pscustomobject]@{ Method = $Request.HttpMethod; RawUrl = $Request.RawUrl; Headers = $Headers; Length = $Body.Length; Sha = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Body)).ToLowerInvariant() })
                    $Path = [uri]::UnescapeDataString($Request.Url.AbsolutePath)
                    $Query = $Request.QueryString
                    $Reply = [byte[]]::new(0)
                    if ($Request.HttpMethod -eq 'POST' -and $null -ne $Query['uploads'] -or $Request.RawUrl -like '*?uploads=*') {
                        $Id = [guid]::NewGuid().ToString()
                        $Uploads[$Id] = @{ Path = $Path; Parts = @{}; Type = $Request.ContentType; Meta = $Headers }
                        $Reply = [System.Text.Encoding]::UTF8.GetBytes("<?xml version=`"1.0`" encoding=`"UTF-8`"?><InitiateMultipartUploadResult xmlns=`"http://s3.amazonaws.com/doc/2006-03-01/`"><UploadId>$Id</UploadId></InitiateMultipartUploadResult>")
                    } elseif ($Request.HttpMethod -eq 'PUT' -and $Query['uploadId']) {
                        if ([int]$Query['partNumber'] -eq $Control.FailPart) {
                            $Response.StatusCode = 403
                            $Reply = [System.Text.Encoding]::UTF8.GetBytes('<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>')
                        } else {
                            $ETag = '"' + [Convert]::ToHexString([System.Security.Cryptography.MD5]::HashData($Body)).ToLowerInvariant() + '"'
                            $Uploads[$Query['uploadId']].Parts[[int]$Query['partNumber']] = @{ Data = $Body; ETag = $ETag }
                            $Response.AddHeader('ETag', $ETag)
                        }
                    } elseif ($Request.HttpMethod -eq 'POST' -and $Query['uploadId']) {
                        $Upload = $Uploads[$Query['uploadId']]
                        $Data = [System.IO.MemoryStream]::new()
                        $Ok = $true
                        foreach ($Part in ([xml][System.Text.Encoding]::UTF8.GetString($Body)).CompleteMultipartUpload.Part) {
                            $Stored = $Upload.Parts[[int]$Part.PartNumber]
                            if (-not $Stored -or $Stored.ETag -ne $Part.ETag) { $Ok = $false; break }
                            $Data.Write($Stored.Data, 0, $Stored.Data.Length)
                        }
                        if ($Ok) {
                            $Counter++
                            $Meta = @{}
                            foreach ($Name in $Upload.Meta.Keys) { if ($Name -like 'x-amz-meta-*') { $Meta[$Name] = $Upload.Meta[$Name] } }
                            $Objects[$Upload.Path] = @{ Data = $Data.ToArray(); Version = "v$Counter"; ETag = "`"m$Counter`""; Type = $Upload.Type; Meta = $Meta }
                            $Response.AddHeader('x-amz-version-id', "v$Counter")
                            $Reply = [System.Text.Encoding]::UTF8.GetBytes('<CompleteMultipartUploadResult><ETag>"x"</ETag></CompleteMultipartUploadResult>')
                        } else {
                            $Reply = [System.Text.Encoding]::UTF8.GetBytes('<Error><Code>InvalidPart</Code><Message>bad part</Message></Error>')
                        }
                        $Uploads.Remove($Query['uploadId'])
                    } elseif ($Request.HttpMethod -eq 'DELETE' -and $Query['uploadId']) {
                        $Uploads.Remove($Query['uploadId'])
                        $Response.StatusCode = 204
                    } elseif ($Request.HttpMethod -eq 'GET' -and $Query['list-type']) {
                        $Prefix = '/my-bucket/' + $Query['prefix']
                        $Xml = [System.Text.StringBuilder]::new('<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><IsTruncated>false</IsTruncated>')
                        foreach ($Name in @($Objects.Keys | Sort-Object)) {
                            if (-not $Name.StartsWith($Prefix)) { continue }
                            $null = $Xml.Append('<Contents><Key>').Append([System.Security.SecurityElement]::Escape($Name.Substring(11))).Append('</Key><Size>').Append($Objects[$Name].Data.Length).Append('</Size><LastModified>2026-11-20T10:00:00.000Z</LastModified></Contents>')
                        }
                        $null = $Xml.Append('</ListBucketResult>')
                        $Reply = [System.Text.Encoding]::UTF8.GetBytes($Xml.ToString())
                    } elseif ($Request.HttpMethod -eq 'DELETE') {
                        $Objects.Remove($Path)
                        $Response.StatusCode = 204
                    } elseif ($Request.HttpMethod -eq 'PUT') {
                        $Counter++
                        $Meta = @{}
                        foreach ($Name in $Headers.Keys) { if ($Name -like 'x-amz-meta-*') { $Meta[$Name] = $Headers[$Name] } }
                        $Objects[$Path] = @{ Data = $Body; Version = "v$Counter"; ETag = "`"p$Counter`""; Type = $Request.ContentType; Meta = $Meta }
                        $Response.AddHeader('x-amz-version-id', "v$Counter")
                    } else {
                        $Object = $Objects[$Path]
                        if (-not $Object) {
                            $Response.StatusCode = 404
                            if ($Request.HttpMethod -ne 'HEAD') { $Reply = [System.Text.Encoding]::UTF8.GetBytes('<Error><Code>NoSuchKey</Code><Message>The specified key does not exist.</Message></Error>') }
                        } elseif ($Request.HttpMethod -eq 'GET' -and -not $Request.Headers['Range']) {
                            $Response.AddHeader('x-amz-version-id', $Object.Version)
                            $Reply = $Object.Data
                        } elseif ($Request.HttpMethod -eq 'HEAD') {
                            $Response.ContentLength64 = $Object.Data.Length
                            $Response.ContentType = $Object.Type
                            $Response.AddHeader('ETag', $Object.ETag)
                            $Response.AddHeader('x-amz-version-id', $Object.Version)
                            foreach ($Name in $Object.Meta.Keys) { $Response.AddHeader($Name, $Object.Meta[$Name]) }
                        } elseif ($Request.Headers['If-Match'] -ne $Object.ETag) {
                            $Response.StatusCode = 412
                            $Reply = [System.Text.Encoding]::UTF8.GetBytes('<Error><Code>PreconditionFailed</Code><Message>At least one of the pre-conditions you specified did not hold</Message></Error>')
                        } else {
                            $Range = $Request.Headers['Range'] -replace '^bytes=', ''
                            $Start = [int]$Range.Split('-')[0]
                            $End = [int]$Range.Split('-')[1]
                            $Response.StatusCode = 206
                            $Reply = [byte[]]::new($End - $Start + 1)
                            [System.Array]::Copy($Object.Data, $Start, $Reply, 0, $Reply.Length)
                        }
                    }
                    if ($Reply.Length) { $Response.OutputStream.Write($Reply, 0, $Reply.Length) }
                    $Response.Close()
                }
            }).AddArgument($S3Listener).AddArgument($S3Log).AddArgument($S3Control)
        $script:S3Handle = $S3Server.BeginInvoke()
        $script:LocalS3 = [pscustomobject]@{ Provider = 'S3'; Bucket = 'my-bucket'; Region = 'us-east-1'; AccessKeyId = 'AKIDTEST'; Secret = 'secret/key+value'; Endpoint = "http://127.0.0.1:$S3Port"; ForcePathStyle = $false }

        function Test-S3Log {
            foreach ($Request in $S3Log.ToArray()) {
                $Authorization = $Request.Headers['Authorization']
                $Names = ($Authorization -split 'SignedHeaders=')[1].Split(',')[0].Split(';')
                $Signed = @{}
                foreach ($Name in $Names) { if ($Name -ne 'host') { $Signed[$Name] = $Request.Headers[$Name] } }
                $Expected = Get-CIPPS3Signature -Method $Request.Method -Uri "http://127.0.0.1:$S3Port$($Request.RawUrl)" -Headers $Signed -Region 'us-east-1' -AccessKeyId 'AKIDTEST' -SecretAccessKey 'secret/key+value'
                $Authorization | Should -BeExactly $Expected
                $Request.Headers['x-amz-content-sha256'] | Should -BeExactly $Request.Sha
            }
        }
    }

    AfterAll {
        $S3Listener.Stop()
        $S3Listener.Close()
        $S3Server.Dispose()
    }

    BeforeEach {
        Mock Get-CIPPCloudBackupKey { , ([byte[]]$script:EncKey.Clone()) }
        $S3Control.FailPart = 0
        $Item = $null
        while ($S3Log.TryDequeue([ref]$Item)) { }
    }

    It 'round-trips an encrypted 17 MiB stream through a signed multipart upload and ranged reads under a key with commas' {
        $Key = 'p/c/sharepoint/contoso.sharepoint.com,1111,2222/items/drive/item'
        $Sent = Send-CIPPCloudBackupObjectStream -Destination $LocalS3 -Key $Key -Stream ([CippTestCountingStream]::new(17MB)) -ContentType 'application/pdf' -Metadata @{ Kind = 'file' } -KeyId $EncKeyId -EncryptionKey $EncKey
        $Sent.VersionId | Should -Be 'v1'

        $Log = @($S3Log.ToArray())
        $Log.Method | Should -Be @('POST', 'PUT', 'PUT', 'PUT', 'POST')
        $Log[0].RawUrl | Should -BeExactly '/my-bucket/p/c/sharepoint/contoso.sharepoint.com%2C1111%2C2222/items/drive/item?uploads='
        $Log[1].RawUrl | Should -BeLike '*?partNumber=1&uploadId=*'
        $Log[1].Length | Should -Be 8MB
        Test-S3Log

        $Encrypted = [System.IO.MemoryStream]::new()
        $Received = Receive-CIPPCloudBackupObjectStream -Destination $LocalS3 -Key $Key -OutStream $Encrypted
        $Received.Bytes | Should -Be $Sent.Bytes
        $Received.VersionId | Should -Be 'v1'
        $Received.ContentType | Should -Be 'application/pdf'
        $Received.Metadata.Kind | Should -Be 'file'
        Test-S3Log

        $Encrypted.Position = 0
        $Plain = [System.IO.MemoryStream]::new()
        $null = Unprotect-CIPPCloudBackupStream -InputStream $Encrypted -OutputStream $Plain
        $Plain.Position = 0
        [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Plain)) | Should -Be (Get-SourceHash 17MB)
    }

    It 'aborts the multipart upload when the server rejects a part' {
        $S3Control.FailPart = 2
        { Send-CIPPCloudBackupObjectStream -Destination $LocalS3 -Key 'p/fail' -Stream ([CippTestCountingStream]::new(17MB)) } | Should -Throw '*AccessDenied*'
        $Log = @($S3Log.ToArray())
        $Log[$Log.Count - 1].Method | Should -Be 'DELETE'
        $Log[$Log.Count - 1].RawUrl | Should -BeLike '/my-bucket/p/fail?uploadId=*'
        Test-S3Log
    }

    It 'puts, gets, lists and removes a key with <Name>' -ForEach @(
        @{ Name = 'commas'; Key = 'p/c/sharepoint/contoso.sharepoint.com,1111,2222/items/d/i' }
        @{ Name = 'a Teams thread id'; Key = 'p/c/teams/u/items/19:abc123@thread.v2/1700000000000.json' }
        @{ Name = 'spaces and a plus'; Key = 'p/c/x/items/a b+c/d e.json' }
    ) {
        $Put = Set-CIPPCloudBackupObject -Destination $LocalS3 -Key $Key -Body ([byte[]](1, 2, 3)) -Metadata @{ Kind = 'x' }
        $Put.Key | Should -BeExactly $Key
        $Put.Bytes | Should -Be 3
        $Got = Get-CIPPCloudBackupObject -Destination $LocalS3 -Key $Key
        ($Got.Body -join ',') | Should -Be '1,2,3'
        $Got.VersionId | Should -Be $Put.VersionId
        @(Get-CIPPCloudBackupObjectList -Destination $LocalS3 -Prefix ($Key.Substring(0, $Key.LastIndexOf('/') + 1))).Key | Should -Be @($Key)
        Remove-CIPPCloudBackupObject -Destination $LocalS3 -Key $Key
        Get-CIPPCloudBackupObject -Destination $LocalS3 -Key $Key | Should -BeNullOrEmpty
        { Remove-CIPPCloudBackupObject -Destination $LocalS3 -Key $Key } | Should -Not -Throw
        Test-S3Log
    }

    It 'reads only the requested range and still reports the full size' {
        $null = Send-CIPPCloudBackupObjectStream -Destination $LocalS3 -Key 'p/ranged' -Stream ([CippTestCountingStream]::new(3MB))
        $Item = $null
        while ($S3Log.TryDequeue([ref]$Item)) { }
        $Out = [System.IO.MemoryStream]::new()
        $Received = Receive-CIPPCloudBackupObjectStream -Destination $LocalS3 -Key 'p/ranged' -Offset 1MB -Length 1MB -OutStream $Out
        $Received.Bytes | Should -Be 3MB
        $Out.Length | Should -Be 1MB
        $Out.ToArray()[0] | Should -Be ([CippTestCountingStream]::ValueAt(1MB))
        @($S3Log.ToArray().Where({ $_.Method -eq 'GET' })).Headers.Range | Should -Be "bytes=$(1MB)-$(2MB - 1)"
        Test-S3Log
    }

    It 'reads a small object and returns $null for a missing one' {
        $Put = Send-CIPPCloudBackupObjectStream -Destination $LocalS3 -Key 'p/small,1' -Stream ([System.IO.MemoryStream]::new([byte[]](0..255)))
        $Put.Bytes | Should -Be 256
        $Out = [System.IO.MemoryStream]::new()
        (Receive-CIPPCloudBackupObjectStream -Destination $LocalS3 -Key 'p/small,1' -OutStream $Out).VersionId | Should -Be $Put.VersionId
        ($Out.ToArray() -join ',') | Should -Be ((0..255) -join ',')
        Receive-CIPPCloudBackupObjectStream -Destination $LocalS3 -Key 'p/missing' -OutStream $Out | Should -BeNullOrEmpty
        Test-S3Log
    }
}
