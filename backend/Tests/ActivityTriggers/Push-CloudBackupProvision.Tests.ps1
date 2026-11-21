BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')

    $script:JobId = '99999999-9999-9999-9999-999999999999'
    $script:DestId = '88888888-8888-8888-8888-888888888888'
    $script:Sub = '22222222-2222-2222-2222-222222222222'
    $script:AccountPath = "/subscriptions/$script:Sub/resourcegroups/rg-cipp-cloudbackup/providers/Microsoft.Storage/storageAccounts/cippbkabc"

    function New-ProvisionJob {
        param([int]$ImmutabilityDays = 0)
        $Parameters = [ordered]@{
            Name             = 'Backups'
            SubscriptionId   = $script:Sub
            ResourceGroup    = 'rg-cipp-cloudbackup'
            Region           = 'westeurope'
            Redundancy       = 'Standard_ZRS'
            StorageAccount   = 'cippbkabc'
            Container        = 'cipp-backups'
            ImmutabilityDays = $ImmutabilityDays
            DestinationId    = $script:DestId
        }
        [pscustomobject]@{
            PartitionKey   = 'CloudBackupJob'
            RowKey         = $script:JobId
            Type           = 'Provision'
            Status         = 'Queued'
            SourceTenantId = ''
            TargetTenantId = ''
            Parameters     = ($Parameters | ConvertTo-Json -Compress)
            Steps          = ''
            RequestedBy    = 'admin@partner.com'
            CreatedAt      = '2026-11-20T00:00:00.0000000Z'
            StartedAt      = ''
            CompletedAt    = ''
            Summary        = ''
            Error          = ''
        }
    }

    function Get-FinalJob { @($script:JobWrites.Where({ $_.PartitionKey -eq 'CloudBackupJob' }))[-1] }
    function Get-FinalSteps { @((Get-FinalJob).Steps | ConvertFrom-Json) }
}

Describe 'Push-CloudBackupProvision' {
    BeforeAll {
        $script:SavedEnv = @{ TenantID = $env:TenantID; ApplicationID = $env:ApplicationID }
    }
    AfterAll {
        $env:TenantID = $script:SavedEnv.TenantID
        $env:ApplicationID = $script:SavedEnv.ApplicationID
    }
    BeforeEach {
        $env:TenantID = 'partner-tenant-id'
        $env:ApplicationID = 'cipp-app-id'
        $script:Job = New-ProvisionJob
        $script:Arm = [System.Collections.Generic.List[object]]::new()
        $script:JobWrites = [System.Collections.Generic.List[object]]::new()
        $script:ConfigWrites = [System.Collections.Generic.List[object]]::new()
        $script:FailOn = $null
        $script:TestResults = @([pscustomobject]@{ Write = $true; Read = $true; Delete = $true; Lifecycle = $true; Versioning = 'Enabled'; VersionDelete = $true; ContentReady = $true; Passed = $true; Errors = @() })
        $script:TestCall = 0
        Mock Get-CIPPAzDataTableEntity { $script:Job } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Add-CIPPAzDataTableEntity {
            $Copy = [ordered]@{}
            if ($Entity -is [System.Collections.IDictionary]) { foreach ($Key in $Entity.Keys) { $Copy[$Key] = $Entity[$Key] } } else { foreach ($Property in $Entity.PSObject.Properties) { $Copy[$Property.Name] = $Property.Value } }
            $script:JobWrites.Add([pscustomobject]$Copy)
        } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Add-CIPPAzDataTableEntity { $script:ConfigWrites.Add([pscustomobject]@{ Entity = $Entity; OperationType = $OperationType }) } -ParameterFilter { $TableName -eq 'Config' }
        Mock Invoke-CIPPCloudBackupArmRequest {
            $script:Arm.Add([pscustomobject]@{ Method = $Method ?? 'GET'; Path = $Path; ApiVersion = $ApiVersion; Body = $Body; Wait = [bool]$Wait; AllowStatus = $AllowStatus })
            if ($script:FailOn -and $Path -like $script:FailOn.Path -and ($Method ?? 'GET') -eq $script:FailOn.Method) { throw 'Azure Resource Manager returned 403 (AuthorizationFailed): denied' }
            if (($Method ?? 'GET') -eq 'GET' -and $Path -like '*/resourcegroups/rg-cipp-cloudbackup') { return [pscustomobject]@{ StatusCode = 404; Body = $null } }
            [pscustomobject]@{ StatusCode = 200; Body = [pscustomobject]@{} }
        }
        Mock New-GraphGetRequest { [pscustomobject]@{ id = 'sp-object-id' } }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Id = $script:DestId; Provider = 'AzureBlob'; AuthMode = 'CippApp' } }
        Mock Test-CIPPCloudBackupDestination { $script:TestCall++; $script:TestResults[[Math]::Min($script:TestCall, $script:TestResults.Count) - 1] }
        Mock Start-Sleep { }
        Mock Write-LogMessage { }
    }

    It 'creates every resource in order with the hardened settings and records a completed job' {
        Push-CloudBackupProvision -Item ([pscustomobject]@{ JobId = $script:JobId })

        $Calls = @(@($script:Arm).ForEach({ "$($_.Method) $($_.Path)" }))
        $Calls[0] | Should -Be "GET /subscriptions/$Sub/resourcegroups/rg-cipp-cloudbackup"
        $Calls[1] | Should -Be "PUT /subscriptions/$Sub/resourcegroups/rg-cipp-cloudbackup"
        $Calls[2] | Should -Be "PUT $AccountPath"
        $Calls[3] | Should -Be "PUT $AccountPath/blobServices/default"
        $Calls[4] | Should -Be "PUT $AccountPath/blobServices/default/containers/cipp-backups"
        $Calls[5] | Should -BeLike "PUT $AccountPath/providers/Microsoft.Authorization/roleAssignments/*"
        $Calls[6] | Should -BeLike "PUT $AccountPath/providers/Microsoft.Authorization/roleAssignments/*"
        $Calls.Count | Should -Be 7

        $Group = $script:Arm[1]
        $Group.Body.location | Should -Be 'westeurope'
        $Account = $script:Arm[2]
        $Account.Wait | Should -BeTrue
        $Account.ApiVersion | Should -Be '2025-01-01'
        $Account.Body.kind | Should -Be 'StorageV2'
        $Account.Body.location | Should -Be 'westeurope'
        $Account.Body.sku.name | Should -Be 'Standard_ZRS'
        $Account.Body.properties.allowBlobPublicAccess | Should -BeFalse
        $Account.Body.properties.allowSharedKeyAccess | Should -BeFalse
        $Account.Body.properties.minimumTlsVersion | Should -Be 'TLS1_2'
        $Account.Body.properties.supportsHttpsTrafficOnly | Should -BeTrue
        $Account.Body.properties.encryption.requireInfrastructureEncryption | Should -BeTrue
        $Account.Body.properties.Contains('immutableStorageWithVersioning') | Should -BeFalse
        $script:Arm[3].Body.properties.isVersioningEnabled | Should -BeTrue
        $script:Arm[4].Body.properties.publicAccess | Should -Be 'None'

        $Roles = @($script:Arm[5], $script:Arm[6])
        @($Roles.ForEach({ $_.Body.properties.roleDefinitionId })) | Should -Be @(
            "/subscriptions/$Sub/providers/Microsoft.Authorization/roleDefinitions/b7e6dc6d-f1e8-4753-8033-0f276bb0955b"
            "/subscriptions/$Sub/providers/Microsoft.Authorization/roleDefinitions/17d1049b-9a84-46fb-8f53-869881c3d3ab"
        )
        @($Roles.ForEach({ $_.Body.properties.principalId })) | Should -Be @('sp-object-id', 'sp-object-id')
        @($Roles.ForEach({ $_.Body.properties.principalType })) | Should -Be @('ServicePrincipal', 'ServicePrincipal')
        @($Roles.ForEach({ $_.ApiVersion })) | Should -Be @('2022-04-01', '2022-04-01')
        Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like "*servicePrincipals(appId='cipp-app-id')*" -and $tenantid -eq 'partner-tenant-id' }

        $Row = $script:ConfigWrites[0].Entity
        $Row.PartitionKey | Should -Be 'CloudBackupDestination'
        $Row.RowKey | Should -Be $DestId
        $Row.Provider | Should -Be 'AzureBlob'
        $Row.AuthMode | Should -Be 'CippApp'
        $Row.StorageAccount | Should -Be 'cippbkabc'
        $Row.Container | Should -Be 'cipp-backups'
        $Row.SubscriptionId | Should -Be $Sub
        $Row.ResourceGroup | Should -Be 'rg-cipp-cloudbackup'
        $Row.AzureTenantId | Should -Be 'partner-tenant-id'
        $Row.ClientId | Should -Be 'cipp-app-id'
        $Row.ProvisionedBy | Should -Be 'CIPP'
        $Row.ImmutabilityDays | Should -Be 0
        $Row.Keys | Should -Not -Contain 'Secret'
        $script:ConfigWrites[1].OperationType | Should -Be 'UpsertMerge'
        ($script:ConfigWrites[1].Entity.LastTest | ConvertFrom-Json).Passed | Should -BeTrue

        $Job = Get-FinalJob
        $Job.Status | Should -Be 'Completed'
        $Job.Error | Should -Be ''
        $Steps = Get-FinalSteps
        @($Steps.Name) | Should -Be @('ResourceGroup', 'StorageAccount', 'Versioning', 'Container', 'Immutability', 'RoleAssignments', 'Destination', 'Test')
        @($Steps.Status) | Should -Be @('Completed', 'Completed', 'Completed', 'Completed', 'Skipped', 'Completed', 'Completed', 'Completed')
        $Summary = $Job.Summary | ConvertFrom-Json
        $Summary.DestinationId | Should -Be $DestId
        $Summary.TestPassed | Should -BeTrue
        $Result = @($script:JobWrites.Where({ $_.PartitionKey -eq 'CloudBackupJobResult' }))[0]
        $Result.RowKey | Should -Be $JobId
        ($Result.Result | ConvertFrom-Json).StorageAccount | Should -Be 'cippbkabc'
        Should -Invoke Test-CIPPCloudBackupDestination -Times 1 -Exactly
    }

    It 'turns on version-level immutability and sets an unlocked container policy when asked' {
        $script:Job = New-ProvisionJob -ImmutabilityDays 30

        Push-CloudBackupProvision -Item ([pscustomobject]@{ JobId = $script:JobId })

        $script:Arm[2].Body.properties.immutableStorageWithVersioning.enabled | Should -BeTrue
        $Policy = @($script:Arm.Where({ $_.Path -like '*/immutabilityPolicies/default' }))
        $Policy.Count | Should -Be 1
        $Policy[0].Method | Should -Be 'PUT'
        $Policy[0].Path | Should -Be "$AccountPath/blobServices/default/containers/cipp-backups/immutabilityPolicies/default"
        $Policy[0].Body.properties.immutabilityPeriodSinceCreationInDays | Should -Be 30
        ($Policy[0].Body | ConvertTo-Json -Depth 5) | Should -Not -Match 'Locked'
        @($script:Arm.Where({ $_.Path -like '*/lock*' })).Count | Should -Be 0
        $script:ConfigWrites[0].Entity.ImmutabilityDays | Should -Be 30
        (Get-FinalSteps)[4].Status | Should -Be 'Completed'
    }

    It 'stops at a failed <Step> step, keeps what was created and leaves the fallback data' -ForEach @(
        @{ Step = 'ResourceGroup'; Index = 0; Method = 'PUT'; Path = '*/resourcegroups/rg-cipp-cloudbackup' }
        @{ Step = 'StorageAccount'; Index = 1; Method = 'PUT'; Path = '*/storageAccounts/cippbkabc' }
        @{ Step = 'Versioning'; Index = 2; Method = 'PUT'; Path = '*/blobServices/default' }
        @{ Step = 'Container'; Index = 3; Method = 'PUT'; Path = '*/containers/cipp-backups' }
        @{ Step = 'Immutability'; Index = 4; Method = 'PUT'; Path = '*/immutabilityPolicies/default' }
        @{ Step = 'RoleAssignments'; Index = 5; Method = 'PUT'; Path = '*/roleAssignments/*' }
    ) {
        $script:Job = New-ProvisionJob -ImmutabilityDays 7
        $script:FailOn = @{ Method = $Method; Path = $Path }

        Push-CloudBackupProvision -Item ([pscustomobject]@{ JobId = $script:JobId })

        $Job = Get-FinalJob
        $Job.Status | Should -Be 'Failed'
        $Job.Error | Should -BeLike "$($Step):*AuthorizationFailed*"
        $Steps = Get-FinalSteps
        $Steps[$Index].Name | Should -Be $Step
        $Steps[$Index].Status | Should -Be 'Failed'
        for ($i = 0; $i -lt $Index; $i++) { $Steps[$i].Status | Should -Be 'Completed' }
        for ($i = $Index + 1; $i -lt $Steps.Count; $i++) { $Steps[$i].Status | Should -Be 'Pending' }
        @($script:Arm.Where({ $_.Method -eq 'DELETE' })).Count | Should -Be 0
        $script:ConfigWrites.Count | Should -Be 0
        Should -Invoke Test-CIPPCloudBackupDestination -Times 0 -Exactly
        $Summary = $Job.Summary | ConvertFrom-Json
        $Summary.FailedStep | Should -Be $Step
        $Summary.SubscriptionId | Should -Be $Sub
        $Summary.ResourceGroup | Should -Be 'rg-cipp-cloudbackup'
        $Summary.StorageAccount | Should -Be 'cippbkabc'
        $Summary.Container | Should -Be 'cipp-backups'
        $Summary.Region | Should -Be 'westeurope'
        $Summary.DestinationId | Should -BeNullOrEmpty
    }

    It 'refuses a resource group that appeared after the request' {
        Mock Invoke-CIPPCloudBackupArmRequest { $script:Arm.Add([pscustomobject]@{ Method = $Method ?? 'GET'; Path = $Path }); [pscustomobject]@{ StatusCode = 200; Body = [pscustomobject]@{} } }

        Push-CloudBackupProvision -Item ([pscustomobject]@{ JobId = $script:JobId })

        (Get-FinalJob).Status | Should -Be 'Failed'
        (Get-FinalSteps)[0].Error | Should -BeLike '*already exists*'
        @($script:Arm.Where({ $_.Method -eq 'PUT' })).Count | Should -Be 0
    }

    It 'fails the role step when the app has no service principal' {
        Mock New-GraphGetRequest { }

        Push-CloudBackupProvision -Item ([pscustomobject]@{ JobId = $script:JobId })

        (Get-FinalSteps)[5].Status | Should -Be 'Failed'
        $script:ConfigWrites.Count | Should -Be 0
    }

    It 'treats an existing role assignment as done and refuses other conflicts' {
        Mock Invoke-CIPPCloudBackupArmRequest {
            if ($Path -like '*/roleAssignments/*') { return [pscustomobject]@{ StatusCode = 409; Body = [pscustomobject]@{ error = [pscustomobject]@{ code = 'RoleAssignmentExists'; message = 'exists' } } } }
            if (($Method ?? 'GET') -eq 'GET') { return [pscustomobject]@{ StatusCode = 404; Body = $null } }
            [pscustomobject]@{ StatusCode = 200; Body = $null }
        }
        Push-CloudBackupProvision -Item ([pscustomobject]@{ JobId = $script:JobId })
        (Get-FinalJob).Status | Should -Be 'Completed'

        Mock Invoke-CIPPCloudBackupArmRequest {
            if ($Path -like '*/roleAssignments/*') { return [pscustomobject]@{ StatusCode = 409; Body = [pscustomobject]@{ error = [pscustomobject]@{ code = 'PrincipalNotFound'; message = 'not yet' } } } }
            if (($Method ?? 'GET') -eq 'GET') { return [pscustomobject]@{ StatusCode = 404; Body = $null } }
            [pscustomobject]@{ StatusCode = 200; Body = $null }
        }
        $script:JobWrites.Clear()
        Push-CloudBackupProvision -Item ([pscustomobject]@{ JobId = $script:JobId })
        (Get-FinalSteps)[5].Error | Should -BeLike '*PrincipalNotFound*'
    }

    It 'retries the connection test while the new role assignments are not applied yet' {
        $Denied = [pscustomobject]@{ Write = $false; Passed = $false; Errors = @('Write: Azure Storage returned 403 (AuthorizationPermissionMismatch): denied') }
        $script:TestResults = @($Denied, $Denied, $script:TestResults[0])

        Push-CloudBackupProvision -Item ([pscustomobject]@{ JobId = $script:JobId })

        Should -Invoke Test-CIPPCloudBackupDestination -Times 3 -Exactly
        Should -Invoke Start-Sleep -Times 2 -Exactly -ParameterFilter { $Seconds -eq 30 }
        (Get-FinalJob).Status | Should -Be 'Completed'
    }

    It 'completes with a failed test step after a bounded wait and tells the admin to test again' {
        $script:TestResults = @([pscustomobject]@{ Write = $false; Passed = $false; Errors = @('Write: Azure Storage returned 403 (AuthorizationPermissionMismatch): denied') })

        Push-CloudBackupProvision -Item ([pscustomobject]@{ JobId = $script:JobId })

        Should -Invoke Test-CIPPCloudBackupDestination -Times 8 -Exactly
        Should -Invoke Start-Sleep -Times 7 -Exactly
        $Test = (Get-FinalSteps)[7]
        $Test.Status | Should -Be 'Failed'
        $Test.Message | Should -BeLike '*test the destination again*'
        $Job = Get-FinalJob
        $Job.Status | Should -Be 'Completed'
        ($Job.Summary | ConvertFrom-Json).TestPassed | Should -BeFalse
        ($Job.Summary | ConvertFrom-Json).DestinationId | Should -Be $DestId
        ($script:ConfigWrites[1].Entity.LastTest | ConvertFrom-Json).Passed | Should -BeFalse
    }

    It 'does not wait for a test failure that is not about access' {
        $script:TestResults = @([pscustomobject]@{ Write = $true; Read = $true; Delete = $true; Lifecycle = $false; Passed = $false; Errors = @('Lifecycle: something else') })

        Push-CloudBackupProvision -Item ([pscustomobject]@{ JobId = $script:JobId })

        Should -Invoke Test-CIPPCloudBackupDestination -Times 1 -Exactly
        Should -Invoke Start-Sleep -Times 0 -Exactly
    }

    It 'ignores a job that is not a provisioning job' {
        $script:Job.Type = 'Compare'
        Push-CloudBackupProvision -Item ([pscustomobject]@{ JobId = $script:JobId })
        Should -Invoke Invoke-CIPPCloudBackupArmRequest -Times 0 -Exactly
        $script:JobWrites.Count | Should -Be 0
    }
}
