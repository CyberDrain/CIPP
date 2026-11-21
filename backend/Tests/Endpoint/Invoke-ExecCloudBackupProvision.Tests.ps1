BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')

    $script:Sub = '22222222-2222-2222-2222-222222222222'
    $script:SavedIdentity = @{
        Endpoint = [System.Environment]::GetEnvironmentVariable('IDENTITY_ENDPOINT')
        Header   = [System.Environment]::GetEnvironmentVariable('IDENTITY_HEADER')
    }
    function Set-ManagedIdentity {
        param([switch]$Off)
        [System.Environment]::SetEnvironmentVariable('IDENTITY_ENDPOINT', $(if ($Off) { $null } else { 'http://localhost:42356/msi/token' }))
        [System.Environment]::SetEnvironmentVariable('IDENTITY_HEADER', $(if ($Off) { $null } else { 'secret-header' }))
    }
    function New-Token {
        $Payload = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"oid":"mi-object-id","xms_mirid":"/subscriptions/x/resourcegroups/cipp/providers/Microsoft.Web/sites/cipp"}')).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        "eyJhbGciOiJub25lIn0.$Payload.sig"
    }
    function Invoke-Options { param($Query) Invoke-ListCloudBackupProvisioningOptions -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupProvisioningOptions' -Query $Query) }
    function Invoke-Provision { param($Body) Invoke-ExecCloudBackupProvision -Request (New-CloudBackupRequest -Endpoint 'ExecCloudBackupProvision' -Body $Body) }
    function New-ProvisionBody {
        param([hashtable]$Overrides = @{})
        $Body = @{ Name = 'Backups'; SubscriptionId = $script:Sub; ResourceGroup = 'rg-cipp-cloudbackup'; Region = 'westeurope'; Redundancy = 'Standard_LRS' }
        foreach ($Key in $Overrides.Keys) { $Body[$Key] = $Overrides[$Key] }
        $Body
    }
}

AfterAll {
    [System.Environment]::SetEnvironmentVariable('IDENTITY_ENDPOINT', $script:SavedIdentity.Endpoint)
    [System.Environment]::SetEnvironmentVariable('IDENTITY_HEADER', $script:SavedIdentity.Header)
}

Describe 'Invoke-ListCloudBackupProvisioningOptions' {
    BeforeEach {
        Set-ManagedIdentity
        Mock Get-CIPPAzIdentityToken { New-Token }
        Mock Invoke-CIPPCloudBackupArmRequest {
            [pscustomobject]@{ StatusCode = 200; Body = [pscustomobject]@{ value = @(
                        [pscustomobject]@{ subscriptionId = $script:Sub; displayName = 'Production'; state = 'Enabled' }
                        [pscustomobject]@{ subscriptionId = '33333333-3333-3333-3333-333333333333'; displayName = 'Old'; state = 'Disabled' }
                    )
                }
            }
        } -ParameterFilter { $Path -eq '/subscriptions' }
        Mock Invoke-CIPPCloudBackupArmRequest {
            [pscustomobject]@{ StatusCode = 200; Body = [pscustomobject]@{ value = @(
                        [pscustomobject]@{ name = 'westeurope'; displayName = 'West Europe'; metadata = [pscustomobject]@{ regionType = 'Physical' } }
                        [pscustomobject]@{ name = 'europe'; displayName = 'Europe'; metadata = [pscustomobject]@{ regionType = 'Logical' } }
                    )
                }
            }
        } -ParameterFilter { $Path -like '/subscriptions/*/locations' }
        Mock Write-LogMessage { }
    }

    It 'reports provisioning as unavailable without a managed identity, without calling Azure' {
        Set-ManagedIdentity -Off

        $Response = Invoke-Options

        $Response.StatusCode | Should -Be 200
        $Response.Body.Available | Should -BeFalse
        $Response.Body.Reason | Should -BeLike '*no managed identity*'
        @($Response.Body.Subscriptions).Count | Should -Be 0
        Should -Invoke Invoke-CIPPCloudBackupArmRequest -Times 0 -Exactly
    }

    It 'lists the enabled subscriptions and the managed identity' {
        $Response = Invoke-Options

        $Response.StatusCode | Should -Be 200
        $Response.Body.Available | Should -BeTrue
        $Response.Body.Reason | Should -BeNullOrEmpty
        $Response.Body.ManagedIdentity.PrincipalId | Should -Be 'mi-object-id'
        $Response.Body.ManagedIdentity.ResourceId | Should -BeLike '*/Microsoft.Web/sites/cipp'
        @($Response.Body.Subscriptions).Count | Should -Be 1
        $Response.Body.Subscriptions[0].id | Should -Be $Sub
        $Response.Body.Subscriptions[0].name | Should -Be 'Production'
        @($Response.Body.Regions).Count | Should -Be 0
        Should -Invoke Invoke-CIPPCloudBackupArmRequest -Times 1 -Exactly -ParameterFilter { $ApiVersion -eq '2022-12-01' }
    }

    It 'lists the physical regions of a subscription' {
        $Response = Invoke-Options -Query @{ SubscriptionId = $script:Sub }

        @($Response.Body.Regions).Count | Should -Be 1
        $Response.Body.Regions[0].name | Should -Be 'westeurope'
        $Response.Body.Regions[0].displayName | Should -Be 'West Europe'
    }

    It 'reports a managed identity without subscriptions as unavailable' {
        Mock Invoke-CIPPCloudBackupArmRequest { [pscustomobject]@{ StatusCode = 200; Body = [pscustomobject]@{ value = @() } } } -ParameterFilter { $Path -eq '/subscriptions' }

        $Response = Invoke-Options

        $Response.StatusCode | Should -Be 200
        $Response.Body.Available | Should -BeFalse
        $Response.Body.Reason | Should -BeLike '*no access to any subscription*'
    }

    It 'returns 400 for a bad subscription id and 404 for one the identity cannot see' {
        (Invoke-Options -Query @{ SubscriptionId = 'nope' }).StatusCode | Should -Be 400
        (Invoke-Options -Query @{ SubscriptionId = '44444444-4444-4444-4444-444444444444' }).StatusCode | Should -Be 404
    }

    It 'returns 500 when Azure fails' {
        Mock Invoke-CIPPCloudBackupArmRequest { throw 'Azure Resource Manager returned 500 (InternalError): boom' } -ParameterFilter { $Path -eq '/subscriptions' }

        $Response = Invoke-Options

        $Response.StatusCode | Should -Be 500
        $Response.Body.Results | Should -BeLike '*boom*'
    }
}

Describe 'Invoke-ExecCloudBackupProvision' {
    BeforeEach {
        Set-ManagedIdentity
        $script:JobRows = [System.Collections.Generic.List[object]]::new()
        $script:Started = [System.Collections.Generic.List[object]]::new()
        Mock Invoke-CIPPCloudBackupArmRequest {
            [pscustomobject]@{ StatusCode = 200; Body = [pscustomobject]@{ value = @([pscustomobject]@{ name = 'westeurope'; displayName = 'West Europe' }) } }
        } -ParameterFilter { $Path -like '*/locations' }
        Mock Invoke-CIPPCloudBackupArmRequest { [pscustomobject]@{ StatusCode = 404; Body = $null } } -ParameterFilter { $Path -like '*/resourcegroups/*' }
        Mock Add-CIPPAzDataTableEntity { $script:JobRows.Add($Entity) }
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject) }
        Mock Write-LogMessage { }
    }

    It 'returns 400 for <Case>' -ForEach @(
        @{ Case = 'a missing name'; Overrides = @{ Name = '' } }
        @{ Case = 'a bad subscription id'; Overrides = @{ SubscriptionId = 'abc' } }
        @{ Case = 'a resource group ending in a period'; Overrides = @{ ResourceGroup = 'rg.' } }
        @{ Case = 'a resource group with a slash'; Overrides = @{ ResourceGroup = 'rg/x' } }
        @{ Case = 'a missing region'; Overrides = @{ Region = '' } }
        @{ Case = 'an unknown redundancy'; Overrides = @{ Redundancy = 'Premium_LRS' } }
        @{ Case = 'a bad container name'; Overrides = @{ Container = 'Bad_Name' } }
        @{ Case = 'immutability of 0 days'; Overrides = @{ ImmutabilityDays = 0 } }
        @{ Case = 'immutability over 3650 days'; Overrides = @{ ImmutabilityDays = 3651 } }
        @{ Case = 'immutability that is not a number'; Overrides = @{ ImmutabilityDays = 'ten' } }
    ) {
        $Response = Invoke-Provision -Body (New-ProvisionBody -Overrides $Overrides)

        $Response.StatusCode | Should -Be 400
        Should -Invoke Invoke-CIPPCloudBackupArmRequest -Times 0 -Exactly
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }

    It 'returns 400 without a managed identity' {
        Set-ManagedIdentity -Off
        $Response = Invoke-Provision -Body (New-ProvisionBody)
        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -BeLike '*no managed identity*'
    }

    It 'returns 400 for a region the subscription does not offer' {
        $Response = Invoke-Provision -Body (New-ProvisionBody -Overrides @{ Region = 'mars' })
        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -BeLike '*mars*'
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }

    It 'returns 400 when the managed identity cannot use the subscription' {
        Mock Invoke-CIPPCloudBackupArmRequest { [pscustomobject]@{ StatusCode = 403; Body = $null } } -ParameterFilter { $Path -like '*/locations' }
        (Invoke-Provision -Body (New-ProvisionBody)).StatusCode | Should -Be 400
    }

    It 'refuses a resource group that already exists' {
        Mock Invoke-CIPPCloudBackupArmRequest { [pscustomobject]@{ StatusCode = 200; Body = [pscustomobject]@{ name = 'rg-cipp-cloudbackup' } } } -ParameterFilter { $Path -like '*/resourcegroups/*' }

        $Response = Invoke-Provision -Body (New-ProvisionBody)

        $Response.StatusCode | Should -Be 400
        $Response.Body.Results | Should -BeLike '*already exists*'
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }

    It 'queues the job with defaults and returns 202 with the job id' {
        $Response = Invoke-Provision -Body @{ Name = 'Backups'; SubscriptionId = @{ value = $script:Sub; label = 'Production' }; Region = @{ value = 'westeurope' }; ImmutabilityDays = 30 }

        $Response.StatusCode | Should -Be 202
        $Response.Body.JobId -as [guid] | Should -Not -BeNullOrEmpty
        $Response.Body.Results | Should -BeLike '*rg-cipp-cloudbackup*'
        Should -Invoke Invoke-CIPPCloudBackupArmRequest -Times 1 -Exactly -ParameterFilter { $Path -eq "/subscriptions/$script:Sub/resourcegroups/rg-cipp-cloudbackup" -and $AllowStatus -contains 404 }
        $Row = $script:JobRows[0]
        $Row.PartitionKey | Should -Be 'CloudBackupJob'
        $Row.RowKey | Should -Be $Response.Body.JobId
        $Row.Type | Should -Be 'Provision'
        $Row.Status | Should -Be 'Queued'
        $Row.RequestedBy | Should -Be 'admin@partner.com'
        $Parameters = $Row.Parameters | ConvertFrom-Json
        $Parameters.ResourceGroup | Should -Be 'rg-cipp-cloudbackup'
        $Parameters.Redundancy | Should -Be 'Standard_LRS'
        $Parameters.Container | Should -Be 'cipp-backups'
        $Parameters.ImmutabilityDays | Should -Be 30
        $Parameters.StorageAccount | Should -Match '^cippbk[a-z0-9]{18}$'
        $Parameters.DestinationId -as [guid] | Should -Not -BeNullOrEmpty
        $script:Started[0].Batch[0].FunctionName | Should -Be 'CloudBackupProvision'
        $script:Started[0].Batch[0].JobId | Should -Be $Response.Body.JobId
    }

    It 'returns 500 when Azure fails' {
        Mock Invoke-CIPPCloudBackupArmRequest { throw 'Azure Resource Manager returned 500 (InternalError): boom' } -ParameterFilter { $Path -like '*/locations' }
        $Response = Invoke-Provision -Body (New-ProvisionBody)
        $Response.StatusCode | Should -Be 500
        $Response.Body.JobId | Should -BeNullOrEmpty
    }
}
