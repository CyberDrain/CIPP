BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')

    $script:DestId = '22222222-2222-2222-2222-222222222222'
    function New-AzureBody {
        param([hashtable]$Overrides = @{})
        $Body = @{
            Action         = 'Add'
            Name           = 'Primary blob'
            Provider       = 'AzureBlob'
            StorageAccount = 'cippbackups'
            Container      = 'backups'
            SubscriptionId = 'sub'
            ResourceGroup  = 'rg'
            AzureTenantId  = 'tid'
            ClientId       = 'cid'
            ClientSecret   = 'secret-value'
        }
        foreach ($Key in $Overrides.Keys) { $Body[$Key] = $Overrides[$Key] }
        $Body
    }
    function Invoke-Destination { param($Body) Invoke-ExecCloudBackupDestination -Request (New-CloudBackupRequest -Endpoint 'ExecCloudBackupDestination' -Body $Body) }
}

Describe 'Invoke-ExecCloudBackupDestination' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Policies = @()
        Mock Get-CIPPAzDataTableEntity { $script:Policies } -ParameterFilter { $TableName -eq 'Config' }
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add([pscustomobject]@{ Entity = $Entity; OperationType = $OperationType }) }
        Mock Remove-CIPPAzDataTableEntity { }
        Mock Set-CIPPSecret { }
        Mock Remove-CIPPSecret { }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ RowKey = $script:DestId; Name = 'Primary blob'; Provider = 'AzureBlob' } }
        Mock Test-CIPPCloudBackupDestination { [pscustomobject]@{ Write = $true; Read = $true; Delete = $true; Lifecycle = $true; Versioning = 'Enabled'; VersionDelete = $true; ContentReady = $true; Passed = $true; Errors = @() } }
        Mock Write-LogMessage { }
    }

    It 'returns 400 for <Case>' -ForEach @(
        @{ Case = 'an unknown action'; Body = @{ Action = 'Nope' } }
        @{ Case = 'Edit without an id'; Body = @{ Action = 'Edit'; Name = 'x'; Provider = 'S3' } }
        @{ Case = 'a missing name'; Overrides = @{ Name = '' } }
        @{ Case = 'an unknown provider'; Overrides = @{ Provider = 'Dropbox' } }
        @{ Case = 'missing Azure fields'; Overrides = @{ Container = '' } }
        @{ Case = 'Add without a secret'; Overrides = @{ ClientSecret = '' } }
        @{ Case = 'Add with the sentinel as secret'; Overrides = @{ ClientSecret = 'SentToKeyVault' } }
        @{ Case = 'a bad storage account name'; Overrides = @{ StorageAccount = 'Bad_Name' } }
        @{ Case = 'S3 without a bucket'; Body = @{ Action = 'Add'; Name = 'x'; Provider = 'S3'; AccessKeyId = 'AK'; SecretAccessKey = 'SK' } }
        @{ Case = 'S3 with a bad endpoint'; Body = @{ Action = 'Add'; Name = 'x'; Provider = 'S3'; Bucket = 'b'; AccessKeyId = 'AK'; SecretAccessKey = 'SK'; Endpoint = 'not a url' } }
    ) {
        $RequestBody = if ($Body) { $Body } else { New-AzureBody -Overrides $Overrides }
        $Response = Invoke-Destination -Body $RequestBody
        $Response.StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Set-CIPPSecret -Times 0 -Exactly
    }

    It 'adds a destination, stores the secret, runs the test and stores LastTest' {
        $Response = Invoke-Destination -Body (New-AzureBody)

        $Response.StatusCode | Should -Be 200
        $Saved = $script:Writes[0].Entity
        $Saved.PartitionKey | Should -Be 'CloudBackupDestination'
        $Saved.RowKey -as [guid] | Should -Not -BeNullOrEmpty
        $Saved.StorageAccount | Should -Be 'cippbackups'
        $Saved.Bucket | Should -Be ''
        $Saved.Keys | Should -Not -Contain 'ClientSecret'
        Should -Invoke Set-CIPPSecret -Times 1 -Exactly -ParameterFilter { $Name -eq "CloudBackupDest-$($Saved.RowKey)" -and $Value -eq 'secret-value' }
        $TestWrite = $script:Writes[1]
        $TestWrite.OperationType | Should -Be 'UpsertMerge'
        ($TestWrite.Entity.LastTest | ConvertFrom-Json).Passed | Should -BeTrue
        ($TestWrite.Entity.LastTest | ConvertFrom-Json).ContentReady | Should -BeTrue
        ($TestWrite.Entity.LastTest | ConvertFrom-Json).VersionDelete | Should -BeTrue
        $TestWrite.Entity.LastTestedAt | Should -Not -BeNullOrEmpty
        @($Response.Body.Results).Count | Should -Be 1
        $Response.Body.Results[0].state | Should -Be 'success'
    }

    It 'keeps the stored secret on Edit when the sentinel or a blank is sent' -ForEach @(
        @{ Secret = 'SentToKeyVault' }, @{ Secret = '' }
    ) {
        $Response = Invoke-Destination -Body (New-AzureBody -Overrides @{ Action = 'Edit'; Id = $script:DestId; ClientSecret = $Secret })

        $Response.StatusCode | Should -Be 200
        Should -Invoke Set-CIPPSecret -Times 0 -Exactly
        $script:Writes[0].Entity.RowKey | Should -Be $script:DestId
    }

    It 'refuses to change the provider on Edit' {
        $Response = Invoke-Destination -Body @{ Action = 'Edit'; Id = $script:DestId; Name = 'x'; Provider = 'S3'; Bucket = 'b'; AccessKeyId = 'AK'; SecretAccessKey = 'new-secret' }

        $Response.StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'returns 404 when editing a destination that does not exist' {
        Mock Get-CIPPCloudBackupDestination { }

        (Invoke-Destination -Body (New-AzureBody -Overrides @{ Action = 'Edit'; Id = $script:DestId })).StatusCode | Should -Be 404
    }

    It 'saves but returns 207 with one error per failed check when the test fails' {
        Mock Test-CIPPCloudBackupDestination { [pscustomobject]@{ Write = $true; Read = $true; Delete = $true; Lifecycle = $false; Versioning = 'Disabled'; Passed = $false; Errors = @('Lifecycle: AuthorizationFailed') } }

        $Response = Invoke-Destination -Body (New-AzureBody)

        $Response.StatusCode | Should -Be 207
        @($Response.Body.Results.state) | Should -Be @('success', 'error')
        $Response.Body.Results[1].resultText | Should -BeLike '*AuthorizationFailed*'
        ($script:Writes[1].Entity.LastTest | ConvertFrom-Json).Lifecycle | Should -BeFalse
    }

    It 'records a test that throws as a failed test' {
        Mock Test-CIPPCloudBackupDestination { throw 'ContainerNotFound' }

        $Response = Invoke-Destination -Body @{ Action = 'Test'; Id = $script:DestId }

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results[0].resultText | Should -BeLike '*ContainerNotFound*'
        ($script:Writes[0].Entity.LastTest | ConvertFrom-Json).Passed | Should -BeFalse
    }

    It 'Test returns 200 and stores LastTest when every check passes' {
        $Response = Invoke-Destination -Body @{ Action = 'Test'; Id = $script:DestId }

        $Response.StatusCode | Should -Be 200
        $Response.Body.Results[0].resultText | Should -BeLike '*passed*'
        Should -Invoke Test-CIPPCloudBackupDestination -Times 1 -Exactly
        Should -Invoke Get-CIPPCloudBackupDestination -ParameterFilter { $IncludeSecret }
    }

    It 'refuses to delete a destination a policy still uses' {
        $script:Policies = @(New-CloudBackupPolicyRow -DestinationId $script:DestId)

        $Response = Invoke-Destination -Body @{ Action = 'Delete'; Id = $script:DestId }

        $Response.StatusCode | Should -Be 400
        "$($Response.Body.Results)" | Should -BeLike '*Nightly*'
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Remove-CIPPSecret -Times 0 -Exactly
    }

    It 'deletes an unused destination and its secret' {
        $Response = Invoke-Destination -Body @{ Action = 'Delete'; Id = $script:DestId }

        $Response.StatusCode | Should -Be 200
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.RowKey -eq $script:DestId -and $Entity.PartitionKey -eq 'CloudBackupDestination' }
        Should -Invoke Remove-CIPPSecret -Times 1 -Exactly -ParameterFilter { $Name -eq "CloudBackupDest-$($script:DestId)" }
    }

    Context 'CIPP app sign-in' {
        BeforeAll {
            $script:SavedEnv = @{ TenantID = $env:TenantID; ApplicationID = $env:ApplicationID }
            $env:TenantID = 'partner-tenant-id'
            $env:ApplicationID = 'cipp-app-id'
        }
        AfterAll {
            $env:TenantID = $script:SavedEnv.TenantID
            $env:ApplicationID = $script:SavedEnv.ApplicationID
        }

        It 'edits a CippApp destination without a secret, client id or tenant and keeps its mode and provisioning fields' {
            Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ RowKey = $script:DestId; Name = 'Provisioned'; Provider = 'AzureBlob'; AuthMode = 'CippApp'; ProvisionedBy = 'CIPP'; ImmutabilityDays = 30 } }

            $Response = Invoke-Destination -Body @{ Action = 'Edit'; Id = $script:DestId; Name = 'Renamed'; Provider = 'AzureBlob'; StorageAccount = 'cippbkabc'; Container = 'cipp-backups'; SubscriptionId = 'sub'; ResourceGroup = 'rg' }

            $Response.StatusCode | Should -Be 200
            $Saved = $script:Writes[0].Entity
            $Saved.AuthMode | Should -Be 'CippApp'
            $Saved.AzureTenantId | Should -Be 'partner-tenant-id'
            $Saved.ClientId | Should -Be 'cipp-app-id'
            $Saved.ProvisionedBy | Should -Be 'CIPP'
            $Saved.ImmutabilityDays | Should -Be 30
            $Saved.Name | Should -Be 'Renamed'
            Should -Invoke Set-CIPPSecret -Times 0 -Exactly
        }

        It 'refuses to switch a CippApp destination to a service principal without a secret' {
            Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ RowKey = $script:DestId; Name = 'Provisioned'; Provider = 'AzureBlob'; AuthMode = 'CippApp' } }

            $Response = Invoke-Destination -Body (New-AzureBody -Overrides @{ Action = 'Edit'; Id = $script:DestId; AuthMode = 'ServicePrincipal'; ClientSecret = '' })

            $Response.StatusCode | Should -Be 400
            $Response.Body.Results | Should -BeLike '*ClientSecret*'
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }

        It 'switches to a service principal when a secret is given' {
            Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ RowKey = $script:DestId; Name = 'Provisioned'; Provider = 'AzureBlob'; AuthMode = 'CippApp' } }

            $Response = Invoke-Destination -Body (New-AzureBody -Overrides @{ Action = 'Edit'; Id = $script:DestId; AuthMode = 'ServicePrincipal' })

            $Response.StatusCode | Should -Be 200
            $script:Writes[0].Entity.AuthMode | Should -Be 'ServicePrincipal'
            $script:Writes[0].Entity.ClientId | Should -Be 'cid'
            Should -Invoke Set-CIPPSecret -Times 1 -Exactly
        }

        It 'adds a CippApp destination without a secret' {
            $Response = Invoke-Destination -Body (New-AzureBody -Overrides @{ AuthMode = 'CippApp'; ClientSecret = ''; ClientId = ''; AzureTenantId = '' })

            $Response.StatusCode | Should -Be 200
            $script:Writes[0].Entity.AuthMode | Should -Be 'CippApp'
            $script:Writes[0].Entity.ClientId | Should -Be 'cipp-app-id'
            Should -Invoke Set-CIPPSecret -Times 0 -Exactly
        }

        It 'returns 400 for an unknown sign-in mode' {
            (Invoke-Destination -Body (New-AzureBody -Overrides @{ AuthMode = 'Magic' })).StatusCode | Should -Be 400
        }

        It 'keeps an existing service principal destination as it was on Edit' {
            Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ RowKey = $script:DestId; Name = 'Blob'; Provider = 'AzureBlob'; AuthMode = 'ServicePrincipal' } }

            $Response = Invoke-Destination -Body (New-AzureBody -Overrides @{ Action = 'Edit'; Id = $script:DestId; ClientSecret = 'SentToKeyVault' })
            $Response.StatusCode | Should -Be 200
            $script:Writes[0].Entity.AuthMode | Should -Be 'ServicePrincipal'
            $script:Writes[0].Entity.AzureTenantId | Should -Be 'tid'

            $script:Writes.Clear()
            $Missing = Invoke-Destination -Body (New-AzureBody -Overrides @{ Action = 'Edit'; Id = $script:DestId; ClientId = '' })
            $Missing.StatusCode | Should -Be 400
            $Missing.Body.Results | Should -Be 'Missing required fields: ClientId'
        }
    }

    It 'returns 500 when the table write fails' {
        Mock Add-CIPPAzDataTableEntity { throw 'table down' }

        $Response = Invoke-Destination -Body (New-AzureBody)

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results[0].state | Should -Be 'error'
    }
}

Describe 'Invoke-ListCloudBackupDestinations' {
    BeforeEach {
        Mock Get-CIPPAzDataTableEntity { @(New-CloudBackupPolicyRow -DestinationId $script:DestId; New-CloudBackupPolicyRow -Id '33333333-3333-3333-3333-333333333333' -DestinationId $script:DestId) } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPSecret { 'stored' }
        Mock Get-CIPPCloudBackupDestination {
            @(
                [pscustomobject]@{ RowKey = $script:DestId; Name = 'Blob'; Provider = 'AzureBlob'; AuthMode = 'ServicePrincipal'; StorageAccount = 'acct'; Container = 'c'; LastTest = [pscustomobject]@{ Write = $true; Read = $true; Delete = $true; Lifecycle = $true; Versioning = 'Enabled'; ContentReady = $true; VersionDelete = $true; Passed = $true; Errors = @() }; LastTestedAt = '2026-11-01T00:00:00Z' }
                [pscustomobject]@{ RowKey = '55555555-5555-5555-5555-555555555555'; Name = 'Wasabi'; Provider = 'S3'; Bucket = 'bk'; Endpoint = 'https://s3.wasabisys.com'; ForcePathStyle = $true; LastTest = $null }
                [pscustomobject]@{ RowKey = '66666666-6666-6666-6666-666666666666'; Name = 'AWS'; Provider = 'S3'; Bucket = 'bk2'; Region = 'eu-west-1'; LastTest = '{"Passed":false,"Errors":["denied"]}' }
                [pscustomobject]@{ RowKey = '77777777-7777-7777-7777-777777777777'; Name = 'Provisioned'; Provider = 'AzureBlob'; AuthMode = 'CippApp'; ProvisionedBy = 'CIPP'; ImmutabilityDays = 30; StorageAccount = 'cippbkabc'; Container = 'cipp-backups'; LastTest = $null }
            )
        }
    }

    It 'lists destinations with location, secret sentinel, test status and policy counts, never the secret' {
        $Response = Invoke-ListCloudBackupDestinations -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupDestinations')

        $Response.StatusCode | Should -Be 200
        $Rows = @($Response.Body)
        $Rows.Count | Should -Be 4
        $Rows[0].Location | Should -Be 'acct/c'
        $Rows[0].SecretSet | Should -Be 'SentToKeyVault'
        $Rows[0].LastTestStatus | Should -Be 'Passed'
        $Rows[0].PolicyCount | Should -Be 2
        $Rows[1].Location | Should -Be 'bk @ s3.wasabisys.com'
        $Rows[1].LastTestStatus | Should -BeNullOrEmpty
        $Rows[1].ForcePathStyle | Should -BeTrue
        $Rows[2].Location | Should -Be 'bk2 (eu-west-1)'
        $Rows[2].LastTestStatus | Should -Be 'Failed'
        @($Rows[2].LastTest.Errors) | Should -Be @('denied')
        $Rows[0].LastTest.ContentReady | Should -BeTrue
        $Rows[2].LastTest.ContentReady | Should -BeFalse
        $Rows[0].LastTest.VersionDelete | Should -BeTrue
        $Rows[0].AuthMode | Should -Be 'ServicePrincipal'
        $Rows[3].AuthMode | Should -Be 'CippApp'
        $Rows[3].ProvisionedBy | Should -Be 'CIPP'
        $Rows[3].ImmutabilityDays | Should -Be 30
        $Rows[3].SecretSet | Should -BeNullOrEmpty
        $Rows[2].LastTest.VersionDelete | Should -BeNullOrEmpty
        ($Rows | ConvertTo-Json -Depth 5) | Should -Not -Match 'stored'
    }

    It 'returns 400 for an Id that is not a GUID and 404 for an unknown one' {
        (Invoke-ListCloudBackupDestinations -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupDestinations' -Query @{ Id = 'abc' })).StatusCode | Should -Be 400
        Mock Get-CIPPCloudBackupDestination { }
        (Invoke-ListCloudBackupDestinations -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupDestinations' -Query @{ Id = $script:DestId })).StatusCode | Should -Be 404
    }
}
