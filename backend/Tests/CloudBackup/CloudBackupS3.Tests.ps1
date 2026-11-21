BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    foreach ($File in Get-ChildItem (Join-Path $RepoRoot 'Modules/CIPPCore/Public/CloudBackup') -Filter '*S3*.ps1') { . $File.FullName }

    $script:EmptyHash = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
    $script:Ns = 'http://s3.amazonaws.com/doc/2006-03-01/'

    function Get-TestDestination {
        param([hashtable]$Override = @{})
        $Destination = @{ Provider = 'S3'; Bucket = 'my-bucket'; Region = 'eu-west-1'; AccessKeyId = 'AKIDTEST'; Secret = 'secret/key+value'; Endpoint = ''; ForcePathStyle = $false }
        foreach ($Name in $Override.Keys) { $Destination[$Name] = $Override[$Name] }
        [pscustomobject]$Destination
    }

    function Get-S3Error {
        param([string]$Code)
        $Exception = [System.Exception]::new("S3 failed with $Code")
        $Exception.Data['S3ErrorCode'] = $Code
        $Exception
    }

    function Get-XmlResponse {
        param([string]$Xml, [hashtable]$Headers = @{})
        [pscustomobject]@{ StatusCode = 200; Headers = $Headers; Body = [byte[]]::new(0); Xml = [xml]$Xml }
    }
}

Describe 'Get-CIPPS3Signature' {
    It 'matches the AWS published example for <Name>' -ForEach @(
        @{ Name = 'GET Object'; Method = 'GET'; Uri = 'https://examplebucket.s3.amazonaws.com/test.txt'; Extra = @{ Range = 'bytes=0-9' }; Payload = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'; Expected = 'f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41'; SignedHeaders = 'host;range;x-amz-content-sha256;x-amz-date' }
        @{ Name = 'PUT Object'; Method = 'PUT'; Uri = 'https://examplebucket.s3.amazonaws.com/test%24file.text'; Extra = @{ Date = 'Fri, 24 May 2013 00:00:00 GMT'; 'x-amz-storage-class' = 'REDUCED_REDUNDANCY' }; Payload = '44ce7dd67c959e0d3524ffac1771dfbba87d2b6b4b4e99e42034a8b803f8b072'; Expected = '98ad721746da40c64f1a55b78f14c238d841ea1380cd77a1b5971af0ece108bd'; SignedHeaders = 'date;host;x-amz-content-sha256;x-amz-date;x-amz-storage-class' }
        @{ Name = 'GET Bucket Lifecycle'; Method = 'GET'; Uri = 'https://examplebucket.s3.amazonaws.com/?lifecycle'; Extra = @{}; Payload = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'; Expected = 'fea454ca298b7da1c68078a5d1bdbfbbe0d65c699e0f91ac7a200a0136783543'; SignedHeaders = 'host;x-amz-content-sha256;x-amz-date' }
        @{ Name = 'GET Bucket (List Objects)'; Method = 'GET'; Uri = 'https://examplebucket.s3.amazonaws.com/?max-keys=2&prefix=J'; Extra = @{}; Payload = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'; Expected = '34b48302e7b5fa45bde8084f4b7868a86f0a534bc59db6670ed5711ef69dc6f7'; SignedHeaders = 'host;x-amz-content-sha256;x-amz-date' }
    ) {
        $Headers = @{ 'x-amz-date' = '20130524T000000Z'; 'x-amz-content-sha256' = $Payload }
        foreach ($Name in $Extra.Keys) { $Headers[$Name] = $Extra[$Name] }
        $Authorization = Get-CIPPS3Signature -Method $Method -Uri $Uri -Headers $Headers -Region 'us-east-1' -AccessKeyId 'AKIAIOSFODNN7EXAMPLE' -SecretAccessKey 'wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY'
        $Authorization | Should -BeExactly "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,SignedHeaders=$SignedHeaders,Signature=$Expected"
    }

    It 'rejects headers without x-amz-date' {
        { Get-CIPPS3Signature -Method GET -Uri 'https://b.s3.amazonaws.com/' -Headers @{ 'x-amz-content-sha256' = $EmptyHash } -Region 'us-east-1' -AccessKeyId 'A' -SecretAccessKey 'S' } |
            Should -Throw -ExceptionType ([System.ArgumentException])
    }
}

Describe 'Invoke-CIPPS3Request request building' {
    BeforeEach {
        $script:Signed = $null
        Mock Get-CIPPS3Signature {
            $script:Signed = @{ Uri = $Uri; Headers = $Headers; Region = $Region; Method = $Method }
            throw 'captured'
        }
    }

    It 'builds <Name>' -ForEach @(
        @{ Name = 'virtual-hosted style for AWS'; Override = @{}; Key = 'pol/ten ant/a+b.json'; Expected = 'https://my-bucket.s3.eu-west-1.amazonaws.com/pol/ten%20ant/a%2Bb.json'; Region = 'eu-west-1' }
        @{ Name = 'path style when ForcePathStyle is set'; Override = @{ ForcePathStyle = $true }; Key = 'k.json'; Expected = 'https://s3.eu-west-1.amazonaws.com/my-bucket/k.json'; Region = 'eu-west-1' }
        @{ Name = 'path style for a stored string flag'; Override = @{ ForcePathStyle = 'True' }; Key = 'k.json'; Expected = 'https://s3.eu-west-1.amazonaws.com/my-bucket/k.json'; Region = 'eu-west-1' }
        @{ Name = 'path style for a dotted bucket'; Override = @{ Bucket = 'my.bucket' }; Key = 'k.json'; Expected = 'https://s3.eu-west-1.amazonaws.com/my.bucket/k.json'; Region = 'eu-west-1' }
        @{ Name = 'the us-east-1 default region'; Override = @{ Region = '' }; Key = 'k.json'; Expected = 'https://my-bucket.s3.us-east-1.amazonaws.com/k.json'; Region = 'us-east-1' }
        @{ Name = 'path style for a custom endpoint without a scheme'; Override = @{ Endpoint = 's3.wasabisys.com' }; Key = 'k.json'; Expected = 'https://s3.wasabisys.com/my-bucket/k.json'; Region = 'eu-west-1' }
        @{ Name = 'path style for an http endpoint with a port'; Override = @{ Endpoint = 'http://minio.local:9000/'; Region = 'auto' }; Key = 'k.json'; Expected = 'http://minio.local:9000/my-bucket/k.json'; Region = 'auto' }
        @{ Name = 'a bucket-level path style request'; Override = @{ Endpoint = 'https://acct.r2.cloudflarestorage.com' }; Key = ''; Expected = 'https://acct.r2.cloudflarestorage.com/my-bucket'; Region = 'eu-west-1' }
    ) {
        { Invoke-CIPPS3Request -Destination (Get-TestDestination $Override) -Method GET -Key $Key } | Should -Throw 'captured'
        $Signed.Uri.AbsoluteUri | Should -BeExactly $Expected
        $Signed.Region | Should -BeExactly $Region
    }

    It 'encodes and sorts the query string' {
        { Invoke-CIPPS3Request -Destination (Get-TestDestination) -Query @{ prefix = 'a/b c'; 'list-type' = '2'; 'continuation-token' = 'x+y=' } } | Should -Throw 'captured'
        $Signed.Uri.Query | Should -BeExactly '?continuation-token=x%2By%3D&list-type=2&prefix=a%2Fb%20c'
    }

    It 'signs the SHA-256 of the body and the caller headers' {
        $Body = [System.Text.Encoding]::UTF8.GetBytes('hello')
        { Invoke-CIPPS3Request -Destination (Get-TestDestination) -Method PUT -Key 'k' -Body $Body -Headers @{ 'Content-MD5' = 'abc'; 'x-amz-meta-policy' = 'p1' } } | Should -Throw 'captured'
        $Signed.Headers['x-amz-content-sha256'] | Should -BeExactly '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824'
        $Signed.Headers['x-amz-date'] | Should -Match '^\d{8}T\d{6}Z$'
        $Signed.Headers['Content-MD5'] | Should -BeExactly 'abc'
        $Signed.Headers['x-amz-meta-policy'] | Should -BeExactly 'p1'
    }

    It 'signs the empty payload hash without a body' {
        { Invoke-CIPPS3Request -Destination (Get-TestDestination) -Key 'k' } | Should -Throw 'captured'
        $Signed.Headers['x-amz-content-sha256'] | Should -BeExactly $EmptyHash
    }

    It 'throws ArgumentException for <Name>' -ForEach @(
        @{ Name = 'a missing secret'; Override = @{ Secret = $null }; Key = 'k' }
        @{ Name = 'a missing bucket'; Override = @{ Bucket = '' }; Key = 'k' }
        @{ Name = 'a bucket with a slash'; Override = @{ Bucket = 'a/b' }; Key = 'k' }
        @{ Name = 'an ftp endpoint'; Override = @{ Endpoint = 'ftp://host' }; Key = 'k' }
        @{ Name = 'a bad region'; Override = @{ Region = 'eu west' }; Key = 'k' }
        @{ Name = 'a dot-dot key segment'; Override = @{}; Key = 'a/../b' }
    ) {
        { Invoke-CIPPS3Request -Destination (Get-TestDestination $Override) -Key $Key } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke Get-CIPPS3Signature -Times 0
    }
}

Describe 'Invoke-CIPPS3Request over HTTP' {
    BeforeAll {
        $Probe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
        $Probe.Start()
        $script:Port = $Probe.LocalEndpoint.Port
        $Probe.Stop()
        $script:Listener = [System.Net.HttpListener]::new()
        $Listener.Prefixes.Add("http://127.0.0.1:$Port/")
        $Listener.Start()
        $script:Received = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $script:Replies = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $script:Server = [powershell]::Create()
        $null = $Server.AddScript({
                param($Listener, $Received, $Replies)
                while ($Listener.IsListening) {
                    try { $Context = $Listener.GetContext() } catch { break }
                    $Buffer = [System.IO.MemoryStream]::new()
                    $Context.Request.InputStream.CopyTo($Buffer)
                    $Headers = @{}
                    foreach ($Name in $Context.Request.Headers.AllKeys) { $Headers[$Name] = $Context.Request.Headers[$Name] }
                    $Received.Enqueue([pscustomobject]@{ Method = $Context.Request.HttpMethod; RawUrl = $Context.Request.RawUrl; Headers = $Headers; Body = $Buffer.ToArray() })
                    $Reply = $null
                    $null = $Replies.TryDequeue([ref]$Reply)
                    $Context.Response.StatusCode = $Reply.Status
                    if ($Reply.ContentType) { $Context.Response.ContentType = $Reply.ContentType }
                    foreach ($Name in $Reply.Headers.Keys) { $Context.Response.AddHeader($Name, $Reply.Headers[$Name]) }
                    if ($Reply.Body.Length) { $Context.Response.OutputStream.Write($Reply.Body, 0, $Reply.Body.Length) }
                    $Context.Response.Close()
                }
            }).AddArgument($Listener).AddArgument($Received).AddArgument($Replies)
        $script:ServerHandle = $Server.BeginInvoke()

        $script:Destination = Get-TestDestination @{ Endpoint = "http://127.0.0.1:$Port"; Region = 'us-east-1' }
        $script:AllBytes = [byte[]](0..255)

        function Add-Reply {
            param([int]$Status = 200, [byte[]]$Body = [byte[]]::new(0), [string]$ContentType, [hashtable]$Headers = @{})
            $Replies.Enqueue([pscustomobject]@{ Status = $Status; Body = $Body; ContentType = $ContentType; Headers = $Headers })
        }

        function Get-Received {
            $Request = $null
            $null = $Received.TryDequeue([ref]$Request)
            $Request
        }

        function Test-ReceivedSignature {
            param($Request)
            $Authorization = $Request.Headers['Authorization']
            $Names = ($Authorization -split 'SignedHeaders=')[1].Split(',')[0].Split(';')
            $Signed = @{}
            foreach ($Name in $Names) { if ($Name -ne 'host') { $Signed[$Name] = $Request.Headers[$Name] } }
            $Expected = Get-CIPPS3Signature -Method $Request.Method -Uri "http://127.0.0.1:$Port$($Request.RawUrl)" -Headers $Signed -Region 'us-east-1' -AccessKeyId 'AKIDTEST' -SecretAccessKey 'secret/key+value'
            $Authorization | Should -BeExactly $Expected
            $Request.Headers['x-amz-content-sha256'] | Should -BeExactly ([Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Request.Body)).ToLowerInvariant())
        }
    }

    AfterAll {
        $Listener.Stop()
        $Listener.Close()
        $Server.Dispose()
    }

    It 'uploads binary bytes with metadata and a verifiable signature' {
        Add-Reply
        Set-CIPPCloudBackupS3Object -Destination $Destination -Key 'pol/ten/config/a b.json.gz' -Body $AllBytes -ContentType 'application/gzip' -Metadata @{ PolicyId = 'p1'; Sha256 = 'abc' }
        $Request = Get-Received
        $Request.Method | Should -Be 'PUT'
        $Request.RawUrl | Should -BeExactly '/my-bucket/pol/ten/config/a%20b.json.gz'
        [Convert]::ToBase64String($Request.Body) | Should -BeExactly ([Convert]::ToBase64String($AllBytes))
        $Request.Headers['Content-Type'] | Should -BeExactly 'application/gzip'
        $Request.Headers['x-amz-meta-PolicyId'] | Should -BeExactly 'p1'
        Test-ReceivedSignature $Request
    }

    It 'downloads binary bytes unchanged with their metadata' {
        Add-Reply -Body $AllBytes -ContentType 'application/octet-stream' -Headers @{ 'x-amz-meta-policyid' = 'p1' }
        $Object = Get-CIPPCloudBackupS3Object -Destination $Destination -Key 'pol/obj.bin'
        [Convert]::ToBase64String($Object.Body) | Should -BeExactly ([Convert]::ToBase64String($AllBytes))
        $Object.Metadata['PolicyId'] | Should -BeExactly 'p1'
        Test-ReceivedSignature (Get-Received)
    }

    It 'sends Content-MD5 with the lifecycle configuration' {
        Add-Reply -Status 404 -ContentType 'application/xml' -Body ([System.Text.Encoding]::UTF8.GetBytes('<?xml version="1.0" encoding="UTF-8"?><Error><Code>NoSuchLifecycleConfiguration</Code><Message>The lifecycle configuration does not exist</Message></Error>'))
        Add-Reply
        Set-CIPPCloudBackupS3RetentionRule -Destination $Destination -RuleName 'cipp-p1' -Prefix 'p1/' -Days 30
        $null = Get-Received
        $Put = Get-Received
        $Put.RawUrl | Should -BeExactly '/my-bucket?lifecycle='
        $Put.Headers['Content-MD5'] | Should -BeExactly ([Convert]::ToBase64String([System.Security.Cryptography.MD5]::HashData($Put.Body)))
        Test-ReceivedSignature $Put
    }

    It 'returns $null for a missing object' {
        Add-Reply -Status 404 -ContentType 'application/xml' -Body ([System.Text.Encoding]::UTF8.GetBytes('<Error><Code>NoSuchKey</Code><Message>The specified key does not exist.</Message></Error>'))
        Get-CIPPCloudBackupS3Object -Destination $Destination -Key 'missing' | Should -BeNullOrEmpty
        $null = Get-Received
    }

    It 'maps NoSuchBucket to ItemNotFoundException' {
        Add-Reply -Status 404 -ContentType 'application/xml' -Body ([System.Text.Encoding]::UTF8.GetBytes('<Error><Code>NoSuchBucket</Code><Message>The specified bucket does not exist</Message></Error>'))
        { Get-CIPPCloudBackupS3Versioning -Destination $Destination } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException]) -ExpectedMessage '*NoSuchBucket*bucket does not exist*'
        $null = Get-Received
    }

    It 'surfaces the provider error code and message without the secret' {
        Add-Reply -Status 403 -ContentType 'application/xml' -Body ([System.Text.Encoding]::UTF8.GetBytes('<Error><Code>SignatureDoesNotMatch</Code><Message>The request signature we calculated does not match</Message></Error>'))
        $Thrown = $null
        try { Get-CIPPCloudBackupS3ObjectList -Destination $Destination -Prefix 'p/' } catch { $Thrown = $_.Exception }
        $Thrown | Should -Not -BeNullOrEmpty
        $Thrown | Should -Not -BeOfType ([System.ArgumentException])
        $Thrown.Message | Should -BeLike '*SignatureDoesNotMatch (HTTP 403): The request signature we calculated does not match*'
        $Thrown.Message | Should -Not -BeLike '*secret/key+value*'
        $Thrown.Data['S3ErrorCode'] | Should -Be 'SignatureDoesNotMatch'
        $null = Get-Received
    }

    It 'reports a non-XML error body' {
        Add-Reply -Status 400 -ContentType 'text/plain' -Body ([System.Text.Encoding]::UTF8.GetBytes('bad gateway thing'))
        { Remove-CIPPCloudBackupS3Object -Destination $Destination -Key 'k' } | Should -Throw '*HTTP400 (HTTP 400): bad gateway thing*'
        $null = Get-Received
    }
}

Describe 'Get-CIPPCloudBackupS3ObjectList' {
    It 'follows continuation tokens across pages' {
        Mock Invoke-CIPPS3Request {
            Get-XmlResponse "<ListBucketResult xmlns='$Ns'><IsTruncated>true</IsTruncated><NextContinuationToken>tok/1=</NextContinuationToken><Contents><Key>p/a.json</Key><Size>10</Size><LastModified>2026-11-01T10:00:00.000Z</LastModified></Contents><Contents><Key>p/b.json</Key><Size>5000000000</Size><LastModified>2026-11-02T10:00:00.000Z</LastModified></Contents></ListBucketResult>"
        } -ParameterFilter { -not $Query['continuation-token'] }
        Mock Invoke-CIPPS3Request {
            Get-XmlResponse "<ListBucketResult xmlns='$Ns'><IsTruncated>false</IsTruncated><Contents><Key>p/c.json</Key><Size>3</Size><LastModified>2026-11-03T10:00:00Z</LastModified></Contents></ListBucketResult>"
        } -ParameterFilter { $Query['continuation-token'] -eq 'tok/1=' }

        $Items = @(Get-CIPPCloudBackupS3ObjectList -Destination (Get-TestDestination) -Prefix 'p/')
        $Items.Key | Should -Be @('p/a.json', 'p/b.json', 'p/c.json')
        $Items[1].Size | Should -BeOfType ([int64])
        $Items[1].Size | Should -Be 5000000000
        $Items[2].LastModified | Should -Be ([datetime]::new(2026, 11, 3, 10, 0, 0, [System.DateTimeKind]::Utc))
        $Items[2].LastModified.Kind | Should -Be 'Utc'
        Should -Invoke Invoke-CIPPS3Request -Times 2 -ParameterFilter { $Query['list-type'] -eq '2' -and $Query['prefix'] -eq 'p/' }
    }

    It 'returns nothing for an empty prefix listing' {
        Mock Invoke-CIPPS3Request { Get-XmlResponse "<ListBucketResult xmlns='$Ns'><IsTruncated>false</IsTruncated><KeyCount>0</KeyCount></ListBucketResult>" }
        @(Get-CIPPCloudBackupS3ObjectList -Destination (Get-TestDestination) -Prefix 'none/').Count | Should -Be 0
    }
}

Describe 'Get-CIPPCloudBackupS3Versioning' {
    It 'returns <Expected> for <Name>' -ForEach @(
        @{ Name = 'an enabled bucket'; Xml = "<VersioningConfiguration xmlns='http://s3.amazonaws.com/doc/2006-03-01/'><Status>Enabled</Status></VersioningConfiguration>"; Expected = 'Enabled' }
        @{ Name = 'a suspended bucket'; Xml = "<VersioningConfiguration xmlns='http://s3.amazonaws.com/doc/2006-03-01/'><Status>Suspended</Status><MfaDelete>Disabled</MfaDelete></VersioningConfiguration>"; Expected = 'Suspended' }
        @{ Name = 'a bucket never versioned'; Xml = "<VersioningConfiguration xmlns='http://s3.amazonaws.com/doc/2006-03-01/'/>"; Expected = 'Disabled' }
    ) {
        Mock Invoke-CIPPS3Request { Get-XmlResponse $Xml }
        Get-CIPPCloudBackupS3Versioning -Destination (Get-TestDestination) | Should -BeExactly $Expected
        Should -Invoke Invoke-CIPPS3Request -Times 1 -ParameterFilter { $Query.ContainsKey('versioning') -and $Method -eq 'GET' }
    }
}

Describe 'S3 retention rules' {
    BeforeAll {
        $script:OtherRule = '<Rule><ID>keep-logs</ID><Filter><And><Prefix>logs/</Prefix><Tag><Key>t</Key><Value>v</Value></Tag></And></Filter><Status>Enabled</Status><Transition><Days>30</Days><StorageClass>GLACIER</StorageClass></Transition></Rule>'
        $script:OurRule = '<Rule><ID>cipp-p1</ID><Filter><Prefix>p1/</Prefix></Filter><Status>Enabled</Status><Expiration><Days>90</Days></Expiration></Rule>'
        function Get-Config { param([string[]]$Rules) "<LifecycleConfiguration xmlns='$Ns'>$($Rules -join '')</LifecycleConfiguration>" }
    }

    BeforeEach {
        $script:Written = $null
        Mock Invoke-CIPPS3Request {
            $script:Written = @{ Body = [System.Text.Encoding]::UTF8.GetString($Body); Headers = $Headers; Bytes = $Body }
        } -ParameterFilter { $Method -eq 'PUT' }
        Mock Invoke-CIPPS3Request { } -ParameterFilter { $Method -eq 'DELETE' }
    }

    Context 'Get-CIPPCloudBackupS3RetentionRule' {
        It 'reads the prefix and days of the named rule' {
            Mock Invoke-CIPPS3Request { Get-XmlResponse (Get-Config $OtherRule, $OurRule) } -ParameterFilter { $Method -eq 'GET' }
            $Rule = Get-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1'
            $Rule.Prefix | Should -BeExactly 'p1/'
            $Rule.Days | Should -Be 90
        }

        It 'reads a legacy rule-level prefix' {
            Mock Invoke-CIPPS3Request { Get-XmlResponse (Get-Config '<Rule><ID>cipp-p1</ID><Prefix>p1/</Prefix><Status>Enabled</Status><Expiration><Days>7</Days></Expiration></Rule>') } -ParameterFilter { $Method -eq 'GET' }
            $Rule = Get-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1'
            $Rule.Prefix | Should -BeExactly 'p1/'
            $Rule.Days | Should -Be 7
        }

        It 'reports no days for a disabled rule' {
            Mock Invoke-CIPPS3Request { Get-XmlResponse (Get-Config $OurRule.Replace('Enabled', 'Disabled')) } -ParameterFilter { $Method -eq 'GET' }
            (Get-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1').Days | Should -BeNullOrEmpty
        }

        It 'returns $null when the rule is absent' {
            Mock Invoke-CIPPS3Request { Get-XmlResponse (Get-Config $OtherRule) } -ParameterFilter { $Method -eq 'GET' }
            Get-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1' | Should -BeNullOrEmpty
        }

        It 'returns $null when the bucket has no lifecycle configuration' {
            Mock Invoke-CIPPS3Request { throw (Get-S3Error 'NoSuchLifecycleConfiguration') } -ParameterFilter { $Method -eq 'GET' }
            Get-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1' | Should -BeNullOrEmpty
        }

        It 'rethrows other errors' {
            Mock Invoke-CIPPS3Request { throw (Get-S3Error 'AccessDenied') } -ParameterFilter { $Method -eq 'GET' }
            { Get-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1' } | Should -Throw '*AccessDenied*'
        }
    }

    Context 'Set-CIPPCloudBackupS3RetentionRule' {
        It 'replaces our rule and keeps every other rule unchanged' {
            Mock Invoke-CIPPS3Request { Get-XmlResponse (Get-Config $OtherRule, $OurRule) } -ParameterFilter { $Method -eq 'GET' }
            Set-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1' -Prefix 'p1/' -Days 30

            $Doc = [xml]$Written.Body
            $Rules = @($Doc.LifecycleConfiguration.Rule)
            $Rules.Count | Should -Be 2
            $Rules[0].OuterXml | Should -BeExactly ([xml](Get-Config $OtherRule)).LifecycleConfiguration.Rule.OuterXml
            $Rules[1]['ID'].InnerText | Should -BeExactly 'cipp-p1'
            $Rules[1]['Filter']['Prefix'].InnerText | Should -BeExactly 'p1/'
            $Rules[1]['Expiration']['Days'].InnerText | Should -BeExactly '30'
            $Rules[1]['Status'].InnerText | Should -BeExactly 'Enabled'
            $Doc.DocumentElement.NamespaceURI | Should -BeExactly $Ns
            $Written.Headers['Content-MD5'] | Should -BeExactly ([Convert]::ToBase64String([System.Security.Cryptography.MD5]::HashData($Written.Bytes)))
            $Written.Headers['Content-Type'] | Should -BeExactly 'application/xml'
        }

        It 'creates the configuration when the bucket has none' {
            Mock Invoke-CIPPS3Request { throw (Get-S3Error 'NoSuchLifecycleConfiguration') } -ParameterFilter { $Method -eq 'GET' }
            Set-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1' -Prefix 'p1/' -Days 90
            @(([xml]$Written.Body).LifecycleConfiguration.Rule).Count | Should -Be 1
        }

        It 'writes a legacy prefix when the existing rules use one' {
            Mock Invoke-CIPPS3Request { Get-XmlResponse (Get-Config '<Rule><ID>old</ID><Prefix>tmp/</Prefix><Status>Enabled</Status><Expiration><Days>1</Days></Expiration></Rule>') } -ParameterFilter { $Method -eq 'GET' }
            Set-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1' -Prefix 'p1/' -Days 90
            $Ours = @(([xml]$Written.Body).LifecycleConfiguration.Rule)[1]
            $Ours['Prefix'].InnerText | Should -BeExactly 'p1/'
            $Ours['Filter'] | Should -BeNullOrEmpty
        }

        It 'passes the transition minimum object size setting back' {
            Mock Invoke-CIPPS3Request { Get-XmlResponse (Get-Config $OtherRule) @{ 'x-amz-transition-default-minimum-object-size' = 'varies_by_storage_class' } } -ParameterFilter { $Method -eq 'GET' }
            Set-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1' -Prefix 'p1/' -Days 90
            $Written.Headers['x-amz-transition-default-minimum-object-size'] | Should -BeExactly 'varies_by_storage_class'
        }

        It 'rejects days below 1' {
            { Set-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1' -Prefix 'p1/' -Days 0 } | Should -Throw -ExceptionType ([System.ArgumentException])
        }

        It 'rethrows a missing bucket' {
            Mock Invoke-CIPPS3Request { throw [System.Management.Automation.ItemNotFoundException]::new('NoSuchBucket') } -ParameterFilter { $Method -eq 'GET' }
            { Set-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1' -Prefix 'p1/' -Days 30 } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
        }
    }

    Context 'Remove-CIPPCloudBackupS3RetentionRule' {
        It 'removes only our rule' {
            Mock Invoke-CIPPS3Request { Get-XmlResponse (Get-Config $OurRule, $OtherRule) } -ParameterFilter { $Method -eq 'GET' }
            Remove-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1'
            $Rules = @(([xml]$Written.Body).LifecycleConfiguration.Rule)
            $Rules.Count | Should -Be 1
            $Rules[0]['ID'].InnerText | Should -BeExactly 'keep-logs'
            Should -Invoke Invoke-CIPPS3Request -Times 0 -ParameterFilter { $Method -eq 'DELETE' }
        }

        It 'deletes the configuration when our rule was the last one' {
            Mock Invoke-CIPPS3Request { Get-XmlResponse (Get-Config $OurRule) } -ParameterFilter { $Method -eq 'GET' }
            Remove-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1'
            Should -Invoke Invoke-CIPPS3Request -Times 1 -ParameterFilter { $Method -eq 'DELETE' -and $Query.ContainsKey('lifecycle') }
            $Written | Should -BeNullOrEmpty
        }

        It 'writes nothing when the rule is absent' {
            Mock Invoke-CIPPS3Request { Get-XmlResponse (Get-Config $OtherRule) } -ParameterFilter { $Method -eq 'GET' }
            Remove-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1'
            Should -Invoke Invoke-CIPPS3Request -Times 0 -ParameterFilter { $Method -in @('PUT', 'DELETE') }
        }

        It 'writes nothing when the bucket has no lifecycle configuration' {
            Mock Invoke-CIPPS3Request { throw (Get-S3Error 'NoSuchLifecycleConfiguration') } -ParameterFilter { $Method -eq 'GET' }
            Remove-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1'
            Should -Invoke Invoke-CIPPS3Request -Times 0 -ParameterFilter { $Method -in @('PUT', 'DELETE') }
        }
    }
}

Describe 'S3 object helpers' {
    It 'rejects metadata the S3 header format cannot carry' {
        Mock Invoke-CIPPS3Request { }
        { Set-CIPPCloudBackupS3Object -Destination (Get-TestDestination) -Key 'k' -Body ([byte[]]@(1)) -Metadata @{ Name = "caf$([char]0xE9)" } } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke Invoke-CIPPS3Request -Times 0
    }

    It 'uploads an empty body with the default content type' {
        Mock Invoke-CIPPS3Request { }
        Set-CIPPCloudBackupS3Object -Destination (Get-TestDestination) -Key 'k' -Body ([byte[]]::new(0))
        Should -Invoke Invoke-CIPPS3Request -Times 1 -ParameterFilter { $Method -eq 'PUT' -and $Body.Length -eq 0 -and $Headers['Content-Type'] -eq 'application/octet-stream' }
    }

    It 'deletes by key' {
        Mock Invoke-CIPPS3Request { }
        Remove-CIPPCloudBackupS3Object -Destination (Get-TestDestination) -Key 'p/k.json'
        Should -Invoke Invoke-CIPPS3Request -Times 1 -ParameterFilter { $Method -eq 'DELETE' -and $Key -eq 'p/k.json' }
    }
}

Describe 'S3 versioned retention and object versions' {
    BeforeAll {
        $script:VersionedRule = '<Rule><ID>cipp-p1</ID><Filter><Prefix>p1/</Prefix></Filter><Status>Enabled</Status><Expiration><ExpiredObjectDeleteMarker>true</ExpiredObjectDeleteMarker></Expiration><NoncurrentVersionExpiration><NoncurrentDays>45</NoncurrentDays></NoncurrentVersionExpiration></Rule>'
        $script:KeepRule = '<Rule><ID>keep-logs</ID><Filter><Prefix>logs/</Prefix></Filter><Status>Enabled</Status><Transition><Days>30</Days><StorageClass>GLACIER</StorageClass></Transition></Rule>'
    }

    BeforeEach {
        $script:Written = $null
        Mock Invoke-CIPPS3Request { $script:Written = [System.Text.Encoding]::UTF8.GetString($Body) } -ParameterFilter { $Method -eq 'PUT' }
    }

    It 'writes noncurrent expiry, delete marker cleanup and multipart abort in Versioned mode' {
        Mock Invoke-CIPPS3Request { Get-XmlResponse "<LifecycleConfiguration xmlns='$Ns'>$KeepRule</LifecycleConfiguration>" } -ParameterFilter { $Method -eq 'GET' }
        Set-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1' -Prefix 'p1/' -Days 45 -Mode Versioned
        $Rules = @(([xml]$Written).LifecycleConfiguration.Rule)
        $Rules[0]['ID'].InnerText | Should -Be 'keep-logs'
        $Ours = $Rules[1]
        $Ours['Filter']['Prefix'].InnerText | Should -Be 'p1/'
        $Ours['Expiration']['Days'] | Should -BeNullOrEmpty
        $Ours['Expiration']['ExpiredObjectDeleteMarker'].InnerText | Should -Be 'true'
        $Ours['NoncurrentVersionExpiration']['NoncurrentDays'].InnerText | Should -Be '45'
        $Ours['AbortIncompleteMultipartUpload']['DaysAfterInitiation'].InnerText | Should -Be '7'
    }

    It 'still writes a plain expiration rule by default' {
        Mock Invoke-CIPPS3Request { Get-XmlResponse "<LifecycleConfiguration xmlns='$Ns'>$KeepRule</LifecycleConfiguration>" } -ParameterFilter { $Method -eq 'GET' }
        Set-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1' -Prefix 'p1/' -Days 30
        $Ours = @(([xml]$Written).LifecycleConfiguration.Rule)[1]
        $Ours['Expiration']['Days'].InnerText | Should -Be '30'
        $Ours['NoncurrentVersionExpiration'] | Should -BeNullOrEmpty
    }

    It 'reads a versioned rule as Mode Versioned with its noncurrent days' {
        Mock Invoke-CIPPS3Request { Get-XmlResponse "<LifecycleConfiguration xmlns='$Ns'>$VersionedRule</LifecycleConfiguration>" } -ParameterFilter { $Method -eq 'GET' }
        $Rule = Get-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1'
        $Rule.Mode | Should -Be 'Versioned'
        $Rule.Days | Should -Be 45
        $Rule.Prefix | Should -Be 'p1/'
    }

    It 'reads an expiration rule as Mode Expire' {
        Mock Invoke-CIPPS3Request { Get-XmlResponse "<LifecycleConfiguration xmlns='$Ns'><Rule><ID>cipp-p1</ID><Filter><Prefix>p1/</Prefix></Filter><Status>Enabled</Status><Expiration><Days>9</Days></Expiration></Rule></LifecycleConfiguration>" } -ParameterFilter { $Method -eq 'GET' }
        $Rule = Get-CIPPCloudBackupS3RetentionRule -Destination (Get-TestDestination) -RuleName 'cipp-p1'
        $Rule.Mode | Should -Be 'Expire'
        $Rule.Days | Should -Be 9
    }

    It 'returns the version id of an upload and $null for an unversioned bucket' {
        Mock Invoke-CIPPS3Request { [pscustomobject]@{ StatusCode = 200; Headers = @{ 'x-amz-version-id' = 'abc' }; Body = [byte[]]::new(0); Xml = $null } } -ParameterFilter { $Method -eq 'PUT' }
        $Result = Set-CIPPCloudBackupS3Object -Destination (Get-TestDestination) -Key 'k' -Body ([byte[]](1, 2, 3))
        $Result.Key | Should -Be 'k'
        $Result.Bytes | Should -Be 3
        $Result.VersionId | Should -Be 'abc'

        Mock Invoke-CIPPS3Request { [pscustomobject]@{ StatusCode = 200; Headers = @{ 'x-amz-version-id' = 'null' }; Body = [byte[]]::new(0); Xml = $null } } -ParameterFilter { $Method -eq 'PUT' }
        (Set-CIPPCloudBackupS3Object -Destination (Get-TestDestination) -Key 'k' -Body ([byte[]](1))).VersionId | Should -BeNullOrEmpty
    }
}
