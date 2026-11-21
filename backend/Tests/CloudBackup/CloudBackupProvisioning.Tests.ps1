BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Folder = Join-Path $BackendRoot 'Modules/CIPPCore/Public/CloudBackup'
    Add-Type -Path (Join-Path $BackendRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll') -ErrorAction SilentlyContinue

    function Get-CIPPClientCredentialToken { param($TenantId, $ClientId, $ClientSecret, $Scope) }
    function Get-GraphToken { param($tenantid, $scope, $AsApp) }
    function Get-CIPPAzIdentityToken { param($ResourceUrl) }
    function Invoke-CIPPRestMethod { param($Uri, $Method, $Headers, $Body, $ContentType, [switch]$SkipHttpErrorCheck) }
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Get-CIPPSecret { param($Name) }
    foreach ($Name in 'Invoke-CIPPCloudBackupArmRequest', 'Invoke-CIPPCloudBackupAzureBlobRequest', 'Invoke-CIPPCloudBackupAzureManagementRequest', 'Remove-CIPPCloudBackupAzureObject', 'Get-CIPPCloudBackupDestination') {
        . (Join-Path $Folder "$Name.ps1")
    }

    function New-ArmResponse {
        param([int]$StatusCode = 200, $Content = '', [hashtable]$Headers = @{})
        [pscustomobject]@{ StatusCode = $StatusCode; Content = $Content; Headers = $Headers }
    }
    function New-BlobResponse {
        param([int]$StatusCode = 200, [hashtable]$Headers = @{})
        [pscustomobject]@{ StatusCode = $StatusCode; Headers = $Headers; RawContentStream = [System.IO.MemoryStream]::new([byte[]]::new(0)) }
    }

    $script:CippApp = [pscustomobject]@{ Provider = 'AzureBlob'; AuthMode = 'CippApp'; StorageAccount = 'cippbkabc'; Container = 'cipp-backups'; SubscriptionId = '22222222-2222-2222-2222-222222222222'; ResourceGroup = 'rg-cipp-cloudbackup'; AzureTenantId = 'partner'; ClientId = 'cipp-app-id' }
    $script:Principal = [pscustomobject]@{ Provider = 'AzureBlob'; AuthMode = 'ServicePrincipal'; StorageAccount = 'cippbackup'; Container = 'backups'; SubscriptionId = '22222222-2222-2222-2222-222222222222'; ResourceGroup = 'rg'; AzureTenantId = 'contoso.onmicrosoft.com'; ClientId = 'app-id'; Secret = 'app-secret' }
}

Describe 'Invoke-CIPPCloudBackupArmRequest' {
    BeforeEach {
        Mock Get-CIPPAzIdentityToken { 'mi-token' }
        Mock Start-Sleep { }
    }

    It 'sends the request with the managed identity token and a JSON body' {
        Mock Invoke-WebRequest { New-ArmResponse -StatusCode 200 -Content '{"name":"rg"}' }

        $Result = Invoke-CIPPCloudBackupArmRequest -Method 'PUT' -Path '/subscriptions/s/resourcegroups/rg' -ApiVersion '2024-03-01' -Body @{ location = 'westeurope' }

        $Result.StatusCode | Should -Be 200
        $Result.Body.name | Should -Be 'rg'
        Should -Invoke Get-CIPPAzIdentityToken -ParameterFilter { $ResourceUrl -eq 'https://management.azure.com/' }
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://management.azure.com/subscriptions/s/resourcegroups/rg?api-version=2024-03-01' -and $Method -eq 'PUT' -and
            $Headers.Authorization -eq 'Bearer mi-token' -and ($Body | ConvertFrom-Json).location -eq 'westeurope' -and $ContentType -eq 'application/json'
        }
    }

    It 'throws the ARM error code and message, or returns an allowed status' {
        Mock Invoke-WebRequest { New-ArmResponse -StatusCode 403 -Content '{"error":{"code":"AuthorizationFailed","message":"no access"}}' }
        $Thrown = $null
        try { Invoke-CIPPCloudBackupArmRequest -Path '/subscriptions/s/locations' -ApiVersion '2022-12-01' } catch { $Thrown = $_ }
        $Thrown.Exception.Message | Should -Be 'Azure Resource Manager returned 403 (AuthorizationFailed): no access'
        $Thrown.Exception.Data['ErrorCode'] | Should -Be 'AuthorizationFailed'

        (Invoke-CIPPCloudBackupArmRequest -Path '/subscriptions/s/locations' -ApiVersion '2022-12-01' -AllowStatus 403).StatusCode | Should -Be 403
    }

    It 'retries throttling with Retry-After' {
        $script:Calls = 0
        Mock Invoke-WebRequest { $script:Calls++; if ($script:Calls -eq 1) { New-ArmResponse -StatusCode 429 -Headers @{ 'Retry-After' = @('7') } } else { New-ArmResponse -StatusCode 200 -Content '{}' } }
        (Invoke-CIPPCloudBackupArmRequest -Path '/subscriptions' -ApiVersion '2022-12-01').StatusCode | Should -Be 200
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
    }

    It 'refuses a path outside subscriptions' {
        { Invoke-CIPPCloudBackupArmRequest -Path 'https://evil.example/x' -ApiVersion '1' } | Should -Throw
    }

    It 'polls the Location header with Retry-After until the operation finishes, then reads the resource' {
        $script:Polls = 0
        Mock Invoke-WebRequest { New-ArmResponse -StatusCode 202 -Headers @{ Location = @('https://management.azure.com/subscriptions/s/providers/Microsoft.Storage/locations/westeurope/asyncoperations/op1?api-version=2025-01-01'); 'Retry-After' = @('17') } } -ParameterFilter { $Method -eq 'PUT' }
        Mock Invoke-WebRequest { $script:Polls++; if ($script:Polls -lt 3) { New-ArmResponse -StatusCode 202 -Headers @{ 'Retry-After' = @('5') } } else { New-ArmResponse -StatusCode 200 -Content '{}' } } -ParameterFilter { $Method -eq 'GET' -and "$Uri" -like '*asyncoperations*' }
        Mock Invoke-WebRequest { New-ArmResponse -StatusCode 200 -Content '{"name":"cippbkabc","properties":{"provisioningState":"Succeeded"}}' } -ParameterFilter { $Method -eq 'GET' -and "$Uri" -like '*storageAccounts/cippbkabc?*' }

        $Result = Invoke-CIPPCloudBackupArmRequest -Method 'PUT' -Path '/subscriptions/s/resourcegroups/rg/providers/Microsoft.Storage/storageAccounts/cippbkabc' -ApiVersion '2025-01-01' -Body @{ kind = 'StorageV2' } -Wait

        $Result.Body.properties.provisioningState | Should -Be 'Succeeded'
        $script:Polls | Should -Be 3
        Should -Invoke Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 17 }
        Should -Invoke Start-Sleep -Times 2 -Exactly -ParameterFilter { $Seconds -eq 5 }
        Should -Invoke Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Method -eq 'GET' -and "$Uri" -like '*storageAccounts/cippbkabc?*' }
    }

    It 'polls Azure-AsyncOperation until Succeeded' {
        Mock Invoke-WebRequest { New-ArmResponse -StatusCode 201 -Headers @{ 'Azure-AsyncOperation' = @('https://management.azure.com/op2') } } -ParameterFilter { $Method -eq 'PUT' }
        $script:Polls = 0
        Mock Invoke-WebRequest { $script:Polls++; New-ArmResponse -StatusCode 200 -Content $(if ($script:Polls -lt 2) { '{"status":"InProgress"}' } else { '{"status":"Succeeded"}' }) } -ParameterFilter { "$Uri" -eq 'https://management.azure.com/op2' }
        Mock Invoke-WebRequest { New-ArmResponse -StatusCode 200 -Content '{"name":"done"}' } -ParameterFilter { $Method -eq 'GET' -and "$Uri" -like '*/thing?*' }

        (Invoke-CIPPCloudBackupArmRequest -Method 'PUT' -Path '/subscriptions/s/thing' -ApiVersion '1' -Wait).Body.name | Should -Be 'done'
        Should -Invoke Start-Sleep -Times 2 -Exactly -ParameterFilter { $Seconds -eq 10 }
    }

    It 'throws the operation error when the long-running operation fails' {
        Mock Invoke-WebRequest { New-ArmResponse -StatusCode 202 -Headers @{ 'Azure-AsyncOperation' = @('https://management.azure.com/op3') } } -ParameterFilter { $Method -eq 'PUT' }
        Mock Invoke-WebRequest { New-ArmResponse -StatusCode 200 -Content '{"status":"Failed","error":{"code":"StorageAccountAlreadyTaken","message":"taken"}}' } -ParameterFilter { $Method -eq 'GET' }

        { Invoke-CIPPCloudBackupArmRequest -Method 'PUT' -Path '/subscriptions/s/thing' -ApiVersion '1' -Wait } | Should -Throw -ExpectedMessage '*StorageAccountAlreadyTaken*taken*'
    }

    It 'never sends the token to an operation URL on another host' {
        Mock Invoke-WebRequest { New-ArmResponse -StatusCode 202 -Headers @{ Location = @('https://evil.example/op') } } -ParameterFilter { $Method -eq 'PUT' }
        Mock Invoke-WebRequest { New-ArmResponse -StatusCode 200 } -ParameterFilter { $Method -eq 'GET' }

        { Invoke-CIPPCloudBackupArmRequest -Method 'PUT' -Path '/subscriptions/s/thing' -ApiVersion '1' -Wait } | Should -Throw -ExpectedMessage '*unexpected operation URL*'
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'GET' }
    }

    It 'stops polling after -MaxPolls' {
        Mock Invoke-WebRequest { New-ArmResponse -StatusCode 202 -Headers @{ Location = @('https://management.azure.com/op4') } }
        { Invoke-CIPPCloudBackupArmRequest -Method 'PUT' -Path '/subscriptions/s/thing' -ApiVersion '1' -Wait -MaxPolls 3 } | Should -Throw -ExpectedMessage '*after 3 checks*'
        Should -Invoke Start-Sleep -Times 3 -Exactly
    }
}

Describe 'CIPP app sign-in for Azure destinations' {
    BeforeAll {
        $script:SavedTenant = $env:TenantID
        $env:TenantID = 'partner-tenant-id'
    }
    AfterAll { $env:TenantID = $script:SavedTenant }
    BeforeEach {
        Mock Get-GraphToken { @{ Authorization = "Bearer cipp-$scope" } }
        Mock Get-CIPPClientCredentialToken { "sp-$Scope" }
    }

    It 'signs storage requests in as CIPP''s app in the partner tenant, without a secret' {
        Mock Invoke-WebRequest { New-BlobResponse -StatusCode 200 }

        $null = Invoke-CIPPCloudBackupAzureBlobRequest -Destination $CippApp -Method 'GET' -Key 'k'

        Should -Invoke Get-GraphToken -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'partner-tenant-id' -and $scope -eq 'https://storage.azure.com/.default' -and $AsApp -eq $true }
        Should -Invoke Get-CIPPClientCredentialToken -Times 0 -Exactly
        Should -Invoke Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://cippbkabc.blob.core.windows.net/cipp-backups/k' -and $Headers.Authorization -eq 'Bearer cipp-https://storage.azure.com/.default' }
    }

    It 'signs management requests in as CIPP''s app in the partner tenant' {
        Mock Invoke-CIPPRestMethod { [pscustomobject]@{ properties = [pscustomobject]@{ isVersioningEnabled = $true } } }

        $null = Invoke-CIPPCloudBackupAzureManagementRequest -Destination $CippApp -Path 'blobServices/default'

        Should -Invoke Get-GraphToken -Times 1 -Exactly -ParameterFilter { $tenantid -eq 'partner-tenant-id' -and $scope -eq 'https://management.azure.com/.default' -and $AsApp -eq $true }
        Should -Invoke Invoke-CIPPRestMethod -ParameterFilter { $Headers.Authorization -eq 'Bearer cipp-https://management.azure.com/.default' }
    }

    It 'keeps service principal destinations on their own client credentials' {
        Mock Invoke-WebRequest { New-BlobResponse -StatusCode 200 }
        Mock Invoke-CIPPRestMethod { [pscustomobject]@{} }

        $null = Invoke-CIPPCloudBackupAzureBlobRequest -Destination $Principal -Method 'GET' -Key 'k'
        $null = Invoke-CIPPCloudBackupAzureManagementRequest -Destination $Principal -Path 'blobServices/default'

        Should -Invoke Get-GraphToken -Times 0 -Exactly
        Should -Invoke Get-CIPPClientCredentialToken -Times 1 -Exactly -ParameterFilter { $TenantId -eq 'contoso.onmicrosoft.com' -and $ClientId -eq 'app-id' -and $ClientSecret -eq 'app-secret' -and $Scope -eq 'https://storage.azure.com/.default' }
        Should -Invoke Get-CIPPClientCredentialToken -Times 1 -Exactly -ParameterFilter { $Scope -eq 'https://management.azure.com/.default' }
        Should -Invoke Invoke-WebRequest -ParameterFilter { $Headers.Authorization -eq 'Bearer sp-https://storage.azure.com/.default' }
    }

    It 'still requires a secret for a service principal destination' {
        $NoSecret = $Principal.PSObject.Copy()
        $NoSecret.Secret = $null
        { Invoke-CIPPCloudBackupAzureBlobRequest -Destination $NoSecret -Key 'k' } | Should -Throw -ExceptionType ([System.ArgumentException])
    }

    It 'puts the storage error code on the exception without changing its message' {
        Mock Invoke-WebRequest { New-BlobResponse -StatusCode 409 -Headers @{ 'x-ms-error-code' = @('BlobImmutableDueToPolicy') } }
        $Thrown = $null
        try { $null = Invoke-CIPPCloudBackupAzureBlobRequest -Destination $CippApp -Method 'DELETE' -Key 'k' } catch { $Thrown = $_ }
        $Thrown.Exception.Message | Should -Be 'Azure Storage returned 409 (BlobImmutableDueToPolicy): no error details were returned'
        $Thrown.Exception.Data['ErrorCode'] | Should -Be 'BlobImmutableDueToPolicy'
        $Thrown.Exception.Data['StatusCode'] | Should -Be 409
    }
}

Describe 'Remove-CIPPCloudBackupAzureObject on an immutable destination' {
    BeforeEach {
        $script:Immutable = $CippApp.PSObject.Copy()
        $script:Immutable | Add-Member -NotePropertyName ImmutabilityDays -NotePropertyValue 30
        $script:Requests = [System.Collections.Generic.List[object]]::new()
        $script:CurrentHeaders = @{}
        Mock Invoke-CIPPCloudBackupAzureBlobRequest {
            $script:Requests.Add([pscustomobject]@{ Method = $Method; Key = $Key; Query = $Query; Headers = $Headers; Body = $Body })
            if ($Method -eq 'HEAD') { return @{ StatusCode = $(if ($script:Missing) { 404 } else { 200 }); Headers = $script:CurrentHeaders; Body = [byte[]]::new(0) } }
            @{ StatusCode = 201; Headers = @{}; Body = [byte[]]::new(0) }
        }
        $script:Missing = $false
    }

    It 'writes an empty marker version instead of setting metadata and deleting' {
        Remove-CIPPCloudBackupAzureObject -Destination $Immutable -Key 'p/a' -Confirm:$false

        @($Requests.Method) | Should -Be @('HEAD', 'PUT')
        $Requests[1].Query | Should -BeNullOrEmpty
        $Requests[1].Body.Length | Should -Be 0
        $Requests[1].Headers.'x-ms-blob-type' | Should -Be 'BlockBlob'
        $Requests[1].Headers.'x-ms-meta-cippdeletedat' | Should -Not -BeNullOrEmpty
    }

    It 'does nothing for a missing blob or one already marked deleted' {
        $script:Missing = $true
        Remove-CIPPCloudBackupAzureObject -Destination $Immutable -Key 'p/a' -Confirm:$false
        $script:Missing = $false
        $script:CurrentHeaders = @{ 'x-ms-meta-cippdeletedat' = @('2026-11-01T00:00:00Z') }
        Remove-CIPPCloudBackupAzureObject -Destination $Immutable -Key 'p/a' -Confirm:$false
        @($Requests.Method) | Should -Be @('HEAD', 'HEAD')
    }

    It 'keeps the metadata marker and delete on a destination without immutability' {
        Remove-CIPPCloudBackupAzureObject -Destination $CippApp -Key 'p/a' -Confirm:$false
        @($Requests.Method) | Should -Be @('PUT', 'DELETE')
        $Requests[0].Query.comp | Should -Be 'metadata'
    }
}

Describe 'Get-CIPPCloudBackupDestination sign-in fields' {
    It 'returns AuthMode, ProvisionedBy and ImmutabilityDays, and reads no secret for CippApp' {
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ RowKey = '11111111-1111-1111-1111-111111111111'; Name = 'Old'; Provider = 'AzureBlob' }
            [pscustomobject]@{ RowKey = '22222222-2222-2222-2222-222222222222'; Name = 'New'; Provider = 'AzureBlob'; AuthMode = 'CippApp'; ProvisionedBy = 'CIPP'; ImmutabilityDays = 30 }
            [pscustomobject]@{ RowKey = '33333333-3333-3333-3333-333333333333'; Name = 'S3'; Provider = 'S3'; ImmutabilityDays = 0 }
        }
        Mock Get-CIPPSecret { 'stored' }

        $Rows = @(Get-CIPPCloudBackupDestination -IncludeSecret)

        $Rows[0].AuthMode | Should -Be 'ServicePrincipal'
        $Rows[0].Secret | Should -Be 'stored'
        $Rows[1].AuthMode | Should -Be 'CippApp'
        $Rows[1].ProvisionedBy | Should -Be 'CIPP'
        $Rows[1].ImmutabilityDays | Should -Be 30
        $null -eq $Rows[1].PSObject.Properties['Secret'] | Should -BeTrue
        $Rows[2].AuthMode | Should -BeNullOrEmpty
        $Rows[2].ImmutabilityDays | Should -BeNullOrEmpty
        Should -Invoke Get-CIPPSecret -Times 2 -Exactly
    }
}
