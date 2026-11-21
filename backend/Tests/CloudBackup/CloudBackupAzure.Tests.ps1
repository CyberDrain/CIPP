BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup'
    Add-Type -Path (Join-Path $BackendRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    function Get-CIPPClientCredentialToken { param($TenantId, $ClientId, $ClientSecret, $Scope) }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Headers, $Body, $ContentType, [switch]$SkipHttpErrorCheck) }
    foreach ($Name in @(
            'Invoke-CIPPCloudBackupAzureBlobRequest', 'Invoke-CIPPCloudBackupAzureManagementRequest',
            'Set-CIPPCloudBackupAzureObject', 'Get-CIPPCloudBackupAzureObject', 'Get-CIPPCloudBackupAzureObjectList', 'Remove-CIPPCloudBackupAzureObject',
            'Get-CIPPCloudBackupAzureRetentionRule', 'Set-CIPPCloudBackupAzureRetentionRule', 'Remove-CIPPCloudBackupAzureRetentionRule', 'Get-CIPPCloudBackupAzureVersioning')) {
        . (Join-Path $Folder "$Name.ps1")
    }

    function New-BlobResponse {
        param([int]$StatusCode = 200, [string]$Content = '', [hashtable]$Headers = @{})
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
        [pscustomobject]@{ StatusCode = $StatusCode; Headers = $Headers; RawContentStream = [System.IO.MemoryStream]::new($Bytes) }
    }

    $script:Destination = [pscustomobject]@{
        Provider       = 'AzureBlob'
        StorageAccount = 'cippbackup'
        Container      = 'backups'
        SubscriptionId = '22222222-2222-2222-2222-222222222222'
        ResourceGroup  = 'rg-backup'
        AzureTenantId  = 'contoso.onmicrosoft.com'
        ClientId       = 'app-id'
        Secret         = 'app-secret'
    }
    $script:PolicyUri = 'https://management.azure.com/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-backup/providers/Microsoft.Storage/storageAccounts/cippbackup/managementPolicies/default?api-version=2023-05-01'
}

Describe 'Azure blob data plane' {
    BeforeEach {
        Mock Get-CIPPClientCredentialToken { "token-for-$Scope" }
    }

    It 'uploads a block blob with a storage token, content type and metadata' {
        Mock Invoke-WebRequest { New-BlobResponse -StatusCode 201 }
        Set-CIPPCloudBackupAzureObject -Destination $Destination -Key 'p1/c1/config/20261120T100000Z/Intune.json.gz' -Body ([byte[]](1, 2, 3)) -ContentType 'application/gzip' -Metadata @{ Area = 'Intune' }

        Should -Invoke Get-CIPPClientCredentialToken -ParameterFilter { $TenantId -eq 'contoso.onmicrosoft.com' -and $ClientId -eq 'app-id' -and $ClientSecret -eq 'app-secret' -and $Scope -eq 'https://storage.azure.com/.default' }
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://cippbackup.blob.core.windows.net/backups/p1/c1/config/20261120T100000Z/Intune.json.gz' -and
            $Method -eq 'PUT' -and $ContentType -eq 'application/gzip' -and ($Body -join ',') -eq '1,2,3' -and
            $Headers.Authorization -eq 'Bearer token-for-https://storage.azure.com/.default' -and
            $Headers.'x-ms-version' -eq '2023-11-03' -and $Headers.'x-ms-blob-type' -eq 'BlockBlob' -and
            $Headers.'x-ms-meta-Area' -eq 'Intune' -and $Headers.'x-ms-date' -and $SkipHttpErrorCheck
        }
    }

    It 'retries throttling and server errors before giving up' {
        Mock Start-Sleep { }
        $script:Attempts = 0
        Mock Invoke-WebRequest { $script:Attempts++; if ($script:Attempts -lt 3) { New-BlobResponse -StatusCode 503 } else { New-BlobResponse -StatusCode 201 } }
        Set-CIPPCloudBackupAzureObject -Destination $Destination -Key 'k' -Body ([byte[]](1))
        Should -Invoke Invoke-WebRequest -Times 3 -Exactly

        Mock Invoke-WebRequest { New-BlobResponse -StatusCode 500 -Content '<Error><Code>InternalError</Code><Message>boom</Message></Error>' }
        { Set-CIPPCloudBackupAzureObject -Destination $Destination -Key 'k' -Body ([byte[]](1)) } | Should -Throw -ExpectedMessage '*500 (InternalError): boom'
        Should -Invoke Invoke-WebRequest -Times 7 -Exactly
    }

    It 'escapes each key segment' {
        Mock Invoke-WebRequest { New-BlobResponse -StatusCode 201 }
        Set-CIPPCloudBackupAzureObject -Destination $Destination -Key 'a b/c#d.json' -Body ([byte[]](1))
        Should -Invoke Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://cippbackup.blob.core.windows.net/backups/a%20b/c%23d.json' -and $ContentType -eq 'application/octet-stream' }
    }

    It 'rejects metadata names Azure does not accept' {
        Mock Invoke-WebRequest { New-BlobResponse -StatusCode 201 }
        { Set-CIPPCloudBackupAzureObject -Destination $Destination -Key 'k' -Body ([byte[]](1)) -Metadata @{ 'bad-name' = 'x' } } | Should -Throw -ExceptionType ([System.ArgumentException])
    }

    It 'downloads a blob as bytes with its metadata' {
        $Bytes = [byte[]](0x1f, 0x8b, 0x00, 0xff)
        Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 200; Headers = @{ 'x-ms-meta-Area' = @('Intune'); 'Content-Type' = @('application/gzip') }; RawContentStream = [System.IO.MemoryStream]::new($Bytes) } }
        $Result = Get-CIPPCloudBackupAzureObject -Destination $Destination -Key 'p1/manifest.json'
        Should -Invoke Invoke-WebRequest -ParameterFilter { $Method -eq 'GET' -and $Uri -eq 'https://cippbackup.blob.core.windows.net/backups/p1/manifest.json' -and -not $Body }
        $Result | Should -BeOfType [pscustomobject]
        $Result.Body.GetType() | Should -Be ([byte[]])
        $Result.Metadata.area | Should -Be 'Intune'
        ($Result.Body -join ',') | Should -Be '31,139,0,255'
        $Result.Metadata.Area | Should -Be 'Intune'
    }

    It 'returns $null for a missing blob' {
        Mock Invoke-WebRequest { New-BlobResponse -StatusCode 404 -Content '<?xml version="1.0" encoding="utf-8"?><Error><Code>BlobNotFound</Code><Message>The specified blob does not exist.</Message></Error>' }
        Get-CIPPCloudBackupAzureObject -Destination $Destination -Key 'missing' | Should -BeNullOrEmpty
    }

    It 'throws ItemNotFoundException for a missing container' {
        Mock Invoke-WebRequest { New-BlobResponse -StatusCode 404 -Content "$([char]0xFEFF)<?xml version=`"1.0`" encoding=`"utf-8`"?><Error><Code>ContainerNotFound</Code><Message>The specified container does not exist.`nRequestId:x</Message></Error>" }
        { Get-CIPPCloudBackupAzureObject -Destination $Destination -Key 'k' } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
    }

    It 'throws the storage error code and message for other failures' {
        Mock Invoke-WebRequest { New-BlobResponse -StatusCode 403 -Content "<?xml version=`"1.0`" encoding=`"utf-8`"?><Error><Code>AuthorizationPermissionMismatch</Code><Message>This request is not authorized to perform this operation using this permission.`nRequestId:x`nTime:y</Message></Error>" }
        { Set-CIPPCloudBackupAzureObject -Destination $Destination -Key 'k' -Body ([byte[]](1)) } | Should -Throw -ExpectedMessage 'Azure Storage returned 403 (AuthorizationPermissionMismatch): This request is not authorized to perform this operation using this permission.'
    }

    It 'lists every page with marker paging' {
        $script:Page = 0
        Mock Invoke-WebRequest {
            $script:Page++
            if ($script:Page -eq 1) {
                New-BlobResponse -Content '<?xml version="1.0" encoding="utf-8"?><EnumerationResults ContainerName="backups"><Prefix>p1/</Prefix><Blobs><Blob><Name>p1/a.json.gz</Name><Properties><Last-Modified>Fri, 20 Nov 2026 10:00:00 GMT</Last-Modified><Content-Length>10</Content-Length></Properties></Blob><Blob><Name>p1/b.json.gz</Name><Properties><Last-Modified>Fri, 20 Nov 2026 11:00:00 GMT</Last-Modified><Content-Length>3000000000</Content-Length></Properties></Blob></Blobs><NextMarker>2!72!MDAw</NextMarker></EnumerationResults>'
            } else {
                New-BlobResponse -Content '<?xml version="1.0" encoding="utf-8"?><EnumerationResults ContainerName="backups"><Blobs><Blob><Name>p1/c.json.gz</Name><Properties><Last-Modified>Fri, 20 Nov 2026 12:00:00 GMT</Last-Modified><Content-Length>5</Content-Length></Properties></Blob></Blobs><NextMarker /></EnumerationResults>'
            }
        }
        $Objects = @(Get-CIPPCloudBackupAzureObjectList -Destination $Destination -Prefix 'p1/')
        $Objects.Key | Should -Be @('p1/a.json.gz', 'p1/b.json.gz', 'p1/c.json.gz')
        $Objects[1].Size | Should -Be 3000000000
        $Objects[0].LastModified | Should -Be ([datetime]::new(2026, 11, 20, 10, 0, 0, [System.DateTimeKind]::Utc))
        $Objects[0].LastModified.Kind | Should -Be 'Utc'
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://cippbackup.blob.core.windows.net/backups?restype=container&comp=list&maxresults=5000&prefix=p1%2F' }
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://cippbackup.blob.core.windows.net/backups?restype=container&comp=list&maxresults=5000&prefix=p1%2F&marker=2%2172%21MDAw' }
    }

    It 'returns nothing for an empty prefix listing' {
        Mock Invoke-WebRequest { New-BlobResponse -Content '<?xml version="1.0" encoding="utf-8"?><EnumerationResults><Blobs /><NextMarker /></EnumerationResults>' }
        @(Get-CIPPCloudBackupAzureObjectList -Destination $Destination -Prefix '').Count | Should -Be 0
        Should -Invoke Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://cippbackup.blob.core.windows.net/backups?restype=container&comp=list&maxresults=5000' }
    }

    It 'deletes a blob with its snapshots and ignores one that is already gone' {
        Mock Invoke-WebRequest { New-BlobResponse -StatusCode 202 }
        Remove-CIPPCloudBackupAzureObject -Destination $Destination -Key 'p1/a.json.gz'
        Should -Invoke Invoke-WebRequest -ParameterFilter { $Method -eq 'DELETE' -and $Uri -eq 'https://cippbackup.blob.core.windows.net/backups/p1/a.json.gz' -and $Headers.'x-ms-delete-snapshots' -eq 'include' }

        Mock Invoke-WebRequest { New-BlobResponse -StatusCode 404 -Content '<Error><Code>BlobNotFound</Code><Message>gone</Message></Error>' }
        { Remove-CIPPCloudBackupAzureObject -Destination $Destination -Key 'p1/a.json.gz' } | Should -Not -Throw
    }

    It 'rejects a storage account name that could redirect the token to another host' {
        Mock Invoke-WebRequest { }
        $Bad = $Destination.PSObject.Copy()
        $Bad.StorageAccount = 'evil.com/x'
        { Get-CIPPCloudBackupAzureObject -Destination $Bad -Key 'k' } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke Get-CIPPClientCredentialToken -Times 0 -Exactly
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'rejects a destination without a secret' {
        $Bad = $Destination.PSObject.Copy()
        $Bad.Secret = $null
        { Get-CIPPCloudBackupAzureObject -Destination $Bad -Key 'k' } | Should -Throw -ExceptionType ([System.ArgumentException])
    }
}

Describe 'Azure lifecycle management and versioning' {
    BeforeEach {
        Mock Get-CIPPClientCredentialToken { "token-for-$Scope" }
        $script:OtherRule = [pscustomobject]@{
            enabled = $true; name = 'someone-elses-rule'; type = 'Lifecycle'
            definition = [pscustomobject]@{
                actions = [pscustomobject]@{ baseBlob = [pscustomobject]@{ tierToCool = [pscustomobject]@{ daysAfterModificationGreaterThan = 30 } } }
                filters = [pscustomobject]@{ blobTypes = @('blockBlob'); prefixMatch = @('logs/') }
            }
        }
        $script:OurRule = [pscustomobject]@{
            enabled = $true; name = 'cipp-p1'; type = 'Lifecycle'
            definition = [pscustomobject]@{
                actions = [pscustomobject]@{ baseBlob = [pscustomobject]@{ delete = [pscustomobject]@{ daysAfterModificationGreaterThan = 30 } } }
                filters = [pscustomobject]@{ blobTypes = @('blockBlob'); prefixMatch = @('backups/p1/') }
            }
        }
        $script:Sent = [System.Collections.Generic.List[object]]::new()
    }

    It 'reads our rule with the container stripped from the prefix' {
        Mock Invoke-CIPPRestMethod { [pscustomobject]@{ properties = [pscustomobject]@{ policy = [pscustomobject]@{ rules = @($script:OtherRule, $script:OurRule) } } } }
        $Rule = Get-CIPPCloudBackupAzureRetentionRule -Destination $Destination -RuleName 'cipp-p1'
        $Rule | Should -BeOfType [pscustomobject]
        $Rule.Prefix | Should -Be 'p1/'
        $Rule.Days | Should -Be 30
        Should -Invoke Invoke-CIPPRestMethod -ParameterFilter { $Uri -eq $PolicyUri -and $Method -eq 'GET' -and $Headers.Authorization -eq 'Bearer token-for-https://management.azure.com/.default' }
    }

    It 'returns $null when the rule or the policy does not exist' {
        Mock Invoke-CIPPRestMethod { [pscustomobject]@{ properties = [pscustomobject]@{ policy = [pscustomobject]@{ rules = @($script:OtherRule) } } } }
        Get-CIPPCloudBackupAzureRetentionRule -Destination $Destination -RuleName 'cipp-p1' | Should -BeNullOrEmpty

        Mock Invoke-CIPPRestMethod { [pscustomobject]@{ error = [pscustomobject]@{ code = 'ManagementPolicyNotFound'; message = 'No ManagementPolicy found' } } }
        Get-CIPPCloudBackupAzureRetentionRule -Destination $Destination -RuleName 'cipp-p1' | Should -BeNullOrEmpty
    }

    It 'throws ItemNotFoundException when the storage account does not exist' {
        Mock Invoke-CIPPRestMethod { [pscustomobject]@{ error = [pscustomobject]@{ code = 'ParentResourceNotFound'; message = 'Parent resource not found' } } }
        { Get-CIPPCloudBackupAzureRetentionRule -Destination $Destination -RuleName 'cipp-p1' } | Should -Throw -ExceptionType ([System.Management.Automation.ItemNotFoundException])
    }

    It 'throws the ARM error for a permission failure' {
        Mock Invoke-CIPPRestMethod { [pscustomobject]@{ error = [pscustomobject]@{ code = 'AuthorizationFailed'; message = 'The client does not have authorization' } } }
        { Get-CIPPCloudBackupAzureRetentionRule -Destination $Destination -RuleName 'cipp-p1' } | Should -Throw -ExpectedMessage 'Azure Resource Manager returned AuthorizationFailed: The client does not have authorization'
    }

    It 'replaces our rule and keeps every other rule' {
        Mock Invoke-CIPPRestMethod {
            if ($Method -eq 'GET') { return [pscustomobject]@{ id = 'x'; properties = [pscustomobject]@{ lastModifiedTime = 'y'; policy = [pscustomobject]@{ rules = @($script:OtherRule, $script:OurRule) } } } }
            $script:Sent.Add(@{ Method = $Method; Uri = $Uri; Body = $Body; ContentType = $ContentType })
        }
        Set-CIPPCloudBackupAzureRetentionRule -Destination $Destination -RuleName 'cipp-p1' -Prefix 'p1/' -Days 90

        $Sent.Count | Should -Be 1
        $Sent[0].Method | Should -Be 'PUT'
        $Sent[0].Uri | Should -Be $PolicyUri
        $Sent[0].ContentType | Should -Be 'application/json'
        $Policy = $Sent[0].Body | ConvertFrom-Json
        $Policy.PSObject.Properties.Name | Should -Be @('properties')
        $Rules = @($Policy.properties.policy.rules)
        $Rules.name | Should -Be @('someone-elses-rule', 'cipp-p1')
        $Rules[0].definition.actions.baseBlob.tierToCool.daysAfterModificationGreaterThan | Should -Be 30
        $Rules[0].definition.filters.prefixMatch | Should -Be @('logs/')
        $Rules[1].enabled | Should -BeTrue
        $Rules[1].type | Should -Be 'Lifecycle'
        $Rules[1].definition.actions.baseBlob.delete.daysAfterModificationGreaterThan | Should -Be 90
        $Rules[1].definition.filters.blobTypes | Should -Be @('blockBlob')
        @($Rules[1].definition.filters.prefixMatch) | Should -Be @('backups/p1/')
    }

    It 'creates the policy when the account has none' {
        Mock Invoke-CIPPRestMethod {
            if ($Method -eq 'GET') { return [pscustomobject]@{ error = [pscustomobject]@{ code = 'ManagementPolicyNotFound'; message = 'none' } } }
            $script:Sent.Add(@{ Method = $Method; Body = $Body })
        }
        Set-CIPPCloudBackupAzureRetentionRule -Destination $Destination -RuleName 'cipp-p1' -Prefix 'p1/' -Days 7
        $Rules = @(($Sent[0].Body | ConvertFrom-Json).properties.policy.rules)
        $Rules.Count | Should -Be 1
        $Rules[0].name | Should -Be 'cipp-p1'
    }

    It 'rejects a rule name Azure does not accept' {
        Mock Invoke-CIPPRestMethod { }
        { Set-CIPPCloudBackupAzureRetentionRule -Destination $Destination -RuleName 'cipp_p1' -Prefix 'p1/' -Days 7 } | Should -Throw -ExceptionType ([System.ArgumentException])
        Should -Invoke Invoke-CIPPRestMethod -Times 0 -Exactly
    }

    It 'removes only our rule' {
        Mock Invoke-CIPPRestMethod {
            if ($Method -eq 'GET') { return [pscustomobject]@{ properties = [pscustomobject]@{ policy = [pscustomobject]@{ rules = @($script:OtherRule, $script:OurRule) } } } }
            $script:Sent.Add(@{ Method = $Method; Body = $Body })
        }
        Remove-CIPPCloudBackupAzureRetentionRule -Destination $Destination -RuleName 'cipp-p1'
        $Sent.Count | Should -Be 1
        $Sent[0].Method | Should -Be 'PUT'
        @(($Sent[0].Body | ConvertFrom-Json).properties.policy.rules).name | Should -Be @('someone-elses-rule')
    }

    It 'deletes the policy when our rule was the only one' {
        Mock Invoke-CIPPRestMethod {
            if ($Method -eq 'GET') { return [pscustomobject]@{ properties = [pscustomobject]@{ policy = [pscustomobject]@{ rules = @($script:OurRule) } } } }
            $script:Sent.Add(@{ Method = $Method; Uri = $Uri; Body = $Body })
        }
        Remove-CIPPCloudBackupAzureRetentionRule -Destination $Destination -RuleName 'cipp-p1'
        $Sent.Count | Should -Be 1
        $Sent[0].Method | Should -Be 'DELETE'
        $Sent[0].Uri | Should -Be $PolicyUri
        $Sent[0].Body | Should -BeNullOrEmpty
    }

    It 'writes nothing when our rule is not there' {
        Mock Invoke-CIPPRestMethod {
            if ($Method -eq 'GET') { return [pscustomobject]@{ properties = [pscustomobject]@{ policy = [pscustomobject]@{ rules = @($script:OtherRule) } } } }
            $script:Sent.Add(@{ Method = $Method })
        }
        Remove-CIPPCloudBackupAzureRetentionRule -Destination $Destination -RuleName 'cipp-p1'
        $Sent.Count | Should -Be 0
    }

    It 'requires a subscription and resource group for lifecycle work' {
        $Bad = $Destination.PSObject.Copy()
        $Bad.SubscriptionId = ''
        { Get-CIPPCloudBackupAzureRetentionRule -Destination $Bad -RuleName 'cipp-p1' } | Should -Throw -ExceptionType ([System.ArgumentException])
    }

    It 'reports versioning as <Expected>' -TestCases @(
        @{ Value = $true; Expected = 'Enabled' }
        @{ Value = $false; Expected = 'Disabled' }
        @{ Value = $null; Expected = 'Disabled' }
    ) {
        Mock Invoke-CIPPRestMethod { [pscustomobject]@{ properties = [pscustomobject]@{ isVersioningEnabled = $Value } } }
        Get-CIPPCloudBackupAzureVersioning -Destination $Destination | Should -Be $Expected
        Should -Invoke Invoke-CIPPRestMethod -ParameterFilter { $Method -eq 'GET' -and $Uri -eq 'https://management.azure.com/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-backup/providers/Microsoft.Storage/storageAccounts/cippbackup/blobServices/default?api-version=2023-05-01' }
    }
}

Describe 'Azure blob bytes over HTTP' {
    BeforeAll {
        $script:RealInvokeWebRequest = Get-Command -Name 'Invoke-WebRequest' -CommandType Cmdlet
        $script:Listener = [System.Net.HttpListener]::new()
        $script:Port = Get-Random -Minimum 20000 -Maximum 60000
        $script:Listener.Prefixes.Add("http://127.0.0.1:$script:Port/")
        $script:Listener.Start()
        $script:Server = [powershell]::Create().AddScript({
                param($Listener)
                $Stored = $null
                for ($i = 0; $i -lt 2; $i++) {
                    $Context = $Listener.GetContext()
                    if ($Context.Request.HttpMethod -eq 'PUT') {
                        $Buffer = [System.IO.MemoryStream]::new()
                        $Context.Request.InputStream.CopyTo($Buffer)
                        $Stored = $Buffer.ToArray()
                        $Context.Response.StatusCode = 201
                    } else {
                        $Context.Response.ContentType = $Context.Request.Headers['x-test-content-type']
                        $Context.Response.AddHeader('x-ms-meta-Area', 'Intune')
                        $Context.Response.OutputStream.Write($Stored, 0, $Stored.Length)
                    }
                    $Context.Response.Close()
                }
            }).AddArgument($script:Listener)
        $script:ServerRun = $script:Server.BeginInvoke()
    }

    AfterAll {
        $script:Listener.Stop()
        $script:Server.Dispose()
    }

    It 'uploads and downloads every byte value unchanged, even when the response claims to be text' {
        Mock Get-CIPPClientCredentialToken { 'token' }
        Mock Invoke-WebRequest {
            $Local = @{} + $PesterBoundParameters
            $Local.Uri = "http://127.0.0.1:$script:Port/blob"
            $Local.Headers = @{ 'x-test-content-type' = 'text/plain; charset=utf-8' }
            & $script:RealInvokeWebRequest @Local
        }
        $Bytes = [byte[]](0..255) + [byte[]](0xEF, 0xBB, 0xBF, 0xC3, 0x28, 0x1F, 0x8B)
        Set-CIPPCloudBackupAzureObject -Destination $Destination -Key 'k.json.gz.enc' -Body $Bytes
        $Result = Get-CIPPCloudBackupAzureObject -Destination $Destination -Key 'k.json.gz.enc'
        $Result.Body.Length | Should -Be $Bytes.Length
        [System.Convert]::ToBase64String($Result.Body) | Should -Be ([System.Convert]::ToBase64String($Bytes))
        $Result.Metadata.Area | Should -Be 'Intune'
    }
}

Describe 'Azure versioned retention and object versions' {
    BeforeEach {
        Mock Get-CIPPClientCredentialToken { "token-for-$Scope" }
        $script:Sent = [System.Collections.Generic.List[object]]::new()
        $script:Existing = [pscustomobject]@{
            enabled = $true; name = 'someone-elses-rule'; type = 'Lifecycle'
            definition = [pscustomobject]@{
                actions = [pscustomobject]@{ baseBlob = [pscustomobject]@{ tierToCool = [pscustomobject]@{ daysAfterModificationGreaterThan = 30 } } }
                filters = [pscustomobject]@{ blobTypes = @('blockBlob'); prefixMatch = @('logs/') }
            }
        }
    }

    It 'writes only a snapshot marker rule in Versioned mode and keeps other rules' {
        Mock Invoke-CIPPRestMethod {
            if ($Method -eq 'GET') { return [pscustomobject]@{ properties = [pscustomobject]@{ policy = [pscustomobject]@{ rules = @($script:Existing) } } } }
            $script:Sent.Add(@{ Method = $Method; Body = $Body })
        }
        Set-CIPPCloudBackupAzureRetentionRule -Destination $Destination -RuleName 'cipp-p1' -Prefix 'p1/' -Days 45 -Mode Versioned
        $Rules = @(($Sent[0].Body | ConvertFrom-Json).properties.policy.rules)
        $Rules.name | Should -Be @('someone-elses-rule', 'cipp-p1')
        $Rules[1].definition.actions.snapshot.delete.daysAfterCreationGreaterThan | Should -Be 45
        $Rules[1].definition.actions.PSObject.Properties.Name | Should -Be @('snapshot')
        @($Rules[1].definition.filters.prefixMatch) | Should -Be @('backups/p1/')
    }

    It 'reports the mode and days of <Mode> rules' -ForEach @(
        @{ Mode = 'Versioned'; Actions = [pscustomobject]@{ snapshot = [pscustomobject]@{ delete = [pscustomobject]@{ daysAfterCreationGreaterThan = 45 } } } }
        @{ Mode = 'Expire'; Actions = [pscustomobject]@{ baseBlob = [pscustomobject]@{ delete = [pscustomobject]@{ daysAfterModificationGreaterThan = 45 } } } }
    ) {
        $Rule = [pscustomobject]@{ enabled = $true; name = 'cipp-p1'; type = 'Lifecycle'; definition = [pscustomobject]@{ actions = $Actions; filters = [pscustomobject]@{ blobTypes = @('blockBlob'); prefixMatch = @('backups/p1/') } } }
        Mock Invoke-CIPPRestMethod { [pscustomobject]@{ properties = [pscustomobject]@{ policy = [pscustomobject]@{ rules = @($Rule) } } } }
        $Result = Get-CIPPCloudBackupAzureRetentionRule -Destination $Destination -RuleName 'cipp-p1'
        $Result.Mode | Should -Be $Mode
        $Result.Days | Should -Be 45
        $Result.Prefix | Should -Be 'p1/'
    }

    It 'returns the version id the service assigned to an upload' {
        Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 201; Headers = @{ 'x-ms-version-id' = @('2026-11-20T10:00:00.0000000Z') }; RawContentStream = [System.IO.MemoryStream]::new() } }
        $Result = Set-CIPPCloudBackupAzureObject -Destination $Destination -Key 'k' -Body ([byte[]](1, 2))
        $Result.Key | Should -Be 'k'
        $Result.Bytes | Should -Be 2
        $Result.VersionId | Should -Be '2026-11-20T10:00:00.0000000Z'

        Mock Invoke-WebRequest { [pscustomobject]@{ StatusCode = 201; Headers = @{}; RawContentStream = [System.IO.MemoryStream]::new() } }
        (Set-CIPPCloudBackupAzureObject -Destination $Destination -Key 'k' -Body ([byte[]](1))).VersionId | Should -BeNullOrEmpty
    }
}
