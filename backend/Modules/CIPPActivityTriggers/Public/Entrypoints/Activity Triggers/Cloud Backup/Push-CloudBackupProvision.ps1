function Push-CloudBackupProvision {
    <#
    .SYNOPSIS
        Creates the Azure storage of a cloud backup provisioning job with CIPP's managed identity and adds it as a destination
    .DESCRIPTION
        Runs the steps in order and records each one on the job. The first failed step stops the job; resources created
        before it are kept, and the job's Summary holds what the manual destination form needs to continue.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param($Item)

    $JobId = "$($Item.JobId)"
    $Table = Get-CIPPTable -TableName 'CloudBackupJobs'
    $Job = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'CloudBackupJob' and RowKey eq '$JobId'")[0]
    if (-not $Job -or $Job.Type -ne 'Provision') { return }

    $Steps = @(foreach ($StepName in 'ResourceGroup', 'StorageAccount', 'Versioning', 'Container', 'Immutability', 'RoleAssignments', 'Destination', 'Test') {
            [ordered]@{ Name = $StepName; Status = 'Pending'; Message = ''; Error = ''; CompletedAt = $null }
        })
    $Summary = [ordered]@{}
    $Status = 'Running'
    $JobError = ''
    $Parameters = $null
    try {
        $Parameters = [CIPP.CippJson]::ConvertFromJson([string]$Job.Parameters)
        $Subscription = "$($Parameters.SubscriptionId)"
        $ResourceGroup = "$($Parameters.ResourceGroup)"
        $Account = "$($Parameters.StorageAccount)"
        $Container = "$($Parameters.Container)"
        $ImmutabilityDays = [int]$Parameters.ImmutabilityDays
        $DestinationId = "$($Parameters.DestinationId)"
        $GroupPath = "/subscriptions/$Subscription/resourcegroups/$ResourceGroup"
        $AccountPath = "$GroupPath/providers/Microsoft.Storage/storageAccounts/$Account"
        $ContainerPath = "$AccountPath/blobServices/default/containers/$Container"
        $StorageApi = '2025-01-01'
        $Summary = [ordered]@{
            SubscriptionId   = $Subscription
            ResourceGroup    = $ResourceGroup
            StorageAccount   = $Account
            Container        = $Container
            Region           = "$($Parameters.Region)"
            Redundancy       = "$($Parameters.Redundancy)"
            ImmutabilityDays = if ($ImmutabilityDays -gt 0) { $ImmutabilityDays } else { $null }
            DestinationId    = $null
            TestPassed       = $false
            FailedStep       = $null
        }
        $Tags = @{ 'managed-by' = 'CIPP'; purpose = 'cipp-cloud-backup' }
        $Job.Status = 'Running'
        $Job.StartedAt = [datetime]::UtcNow.ToString('o')
    } catch {
        $Status = 'Failed'
        $JobError = "The job's parameters could not be read: $($_.Exception.Message)"
    }

    foreach ($Step in $Steps) {
        if ($Status -ne 'Running') { break }
        $Step.Status = 'Running'
        $Job.Steps = [CIPP.CippJson]::ToJson($Steps, 4) ?? (ConvertTo-Json -InputObject $Steps -Depth 4 -Compress)
        Add-CIPPAzDataTableEntity @Table -Entity $Job -Force
        try {
            switch ($Step.Name) {
                'ResourceGroup' {
                    $Existing = Invoke-CIPPCloudBackupArmRequest -Path $GroupPath -ApiVersion '2024-03-01' -AllowStatus 404
                    if ($Existing.StatusCode -ne 404) { throw "Resource group $ResourceGroup already exists. CIPP only creates backup storage in a new resource group." }
                    $null = Invoke-CIPPCloudBackupArmRequest -Method 'PUT' -Path $GroupPath -ApiVersion '2024-03-01' -Body @{ location = $Summary.Region; tags = $Tags }
                    $Step.Message = "Created resource group $ResourceGroup in $($Summary.Region)"
                }
                'StorageAccount' {
                    $Properties = [ordered]@{
                        accessTier                   = 'Hot'
                        allowBlobPublicAccess        = $false
                        allowSharedKeyAccess         = $false
                        allowCrossTenantReplication  = $false
                        defaultToOAuthAuthentication = $true
                        minimumTlsVersion            = 'TLS1_2'
                        supportsHttpsTrafficOnly     = $true
                        encryption                   = [ordered]@{
                            keySource                       = 'Microsoft.Storage'
                            requireInfrastructureEncryption = $true
                            services                        = @{ blob = @{ enabled = $true; keyType = 'Account' }; file = @{ enabled = $true; keyType = 'Account' } }
                        }
                    }
                    if ($ImmutabilityDays -gt 0) { $Properties.immutableStorageWithVersioning = @{ enabled = $true } }
                    $null = Invoke-CIPPCloudBackupArmRequest -Method 'PUT' -Path $AccountPath -ApiVersion $StorageApi -Wait -Body ([ordered]@{
                            location   = $Summary.Region
                            kind       = 'StorageV2'
                            sku        = @{ name = $Summary.Redundancy }
                            tags       = $Tags
                            properties = $Properties
                        })
                    $Step.Message = "Created storage account $Account ($($Summary.Redundancy))"
                }
                'Versioning' {
                    $null = Invoke-CIPPCloudBackupArmRequest -Method 'PUT' -Path "$AccountPath/blobServices/default" -ApiVersion $StorageApi -Body @{ properties = @{ isVersioningEnabled = $true } }
                    $Step.Message = 'Turned on blob versioning'
                }
                'Container' {
                    $null = Invoke-CIPPCloudBackupArmRequest -Method 'PUT' -Path $ContainerPath -ApiVersion $StorageApi -Body @{ properties = @{ publicAccess = 'None' } }
                    $Step.Message = "Created private container $Container"
                }
                'Immutability' {
                    if ($ImmutabilityDays -le 0) {
                        $Step.Status = 'Skipped'
                        $Step.Message = 'Immutability was not requested'
                        break
                    }
                    $null = Invoke-CIPPCloudBackupArmRequest -Method 'PUT' -Path "$ContainerPath/immutabilityPolicies/default" -ApiVersion $StorageApi -Body @{ properties = @{ immutabilityPeriodSinceCreationInDays = $ImmutabilityDays; allowProtectedAppendWrites = $false } }
                    $Step.Message = "Set an unlocked immutability policy of $ImmutabilityDays days on container $Container"
                }
                'RoleAssignments' {
                    $ServicePrincipal = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$($env:ApplicationID)')?`$select=id" -tenantid $env:TenantID -NoAuthCheck $true
                    if (-not $ServicePrincipal.id) { throw "CIPP's app $($env:ApplicationID) has no service principal in the partner tenant." }
                    $Roles = [ordered]@{
                        'Storage Blob Data Owner'     = 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
                        'Storage Account Contributor' = '17d1049b-9a84-46fb-8f53-869881c3d3ab'
                    }
                    foreach ($Role in $Roles.Keys) {
                        $Assignment = Invoke-CIPPCloudBackupArmRequest -Method 'PUT' -Path "$AccountPath/providers/Microsoft.Authorization/roleAssignments/$([guid]::NewGuid())" -ApiVersion '2022-04-01' -AllowStatus 409 -Body @{
                            properties = @{
                                roleDefinitionId = "/subscriptions/$Subscription/providers/Microsoft.Authorization/roleDefinitions/$($Roles[$Role])"
                                principalId      = "$($ServicePrincipal.id)"
                                principalType    = 'ServicePrincipal'
                            }
                        }
                        if ($Assignment.StatusCode -eq 409 -and "$($Assignment.Body.error.code)" -ne 'RoleAssignmentExists') {
                            throw "Azure refused the $Role role assignment ($($Assignment.Body.error.code)): $($Assignment.Body.error.message)"
                        }
                    }
                    $Step.Message = "Gave CIPP's app Storage Blob Data Owner and Storage Account Contributor on $Account"
                }
                'Destination' {
                    $ConfigTable = Get-CIPPTable -TableName 'Config'
                    Add-CIPPAzDataTableEntity @ConfigTable -Entity @{
                        PartitionKey     = 'CloudBackupDestination'
                        RowKey           = $DestinationId
                        Name             = "$($Parameters.Name)"
                        Provider         = 'AzureBlob'
                        AuthMode         = 'CippApp'
                        StorageAccount   = $Account
                        Container        = $Container
                        SubscriptionId   = $Subscription
                        ResourceGroup    = $ResourceGroup
                        AzureTenantId    = "$($env:TenantID)"
                        ClientId         = "$($env:ApplicationID)"
                        Endpoint         = ''
                        Region           = ''
                        Bucket           = ''
                        AccessKeyId      = ''
                        ForcePathStyle   = $false
                        ProvisionedBy    = 'CIPP'
                        ImmutabilityDays = $ImmutabilityDays
                        LastTest         = ''
                        LastTestedAt     = ''
                    } -Force
                    $Summary.DestinationId = $DestinationId
                    $Step.Message = "Added destination $($Parameters.Name)"
                }
                'Test' {
                    $Destination = Get-CIPPCloudBackupDestination -Id $DestinationId -IncludeSecret
                    # New role assignments can take several minutes to apply, so access failures are retried for a bounded time.
                    for ($Attempt = 1; $Attempt -le 8; $Attempt++) {
                        $Test = Test-CIPPCloudBackupDestination -Destination $Destination
                        if ($Test.Passed -or -not (@($Test.Errors) -match 'AuthorizationPermissionMismatch|AuthorizationFailed|\b403\b')) { break }
                        if ($Attempt -lt 8) { Start-Sleep -Seconds 30 }
                    }
                    $LastTest = [ordered]@{
                        Write         = [bool]$Test.Write
                        Read          = [bool]$Test.Read
                        Delete        = [bool]$Test.Delete
                        Lifecycle     = [bool]$Test.Lifecycle
                        Versioning    = $Test.Versioning
                        VersionDelete = [bool]$Test.VersionDelete
                        ContentReady  = [bool]$Test.ContentReady
                        Passed        = [bool]$Test.Passed
                        Errors        = @(@($Test.Errors).Where({ $_ }))
                    }
                    $ConfigTable = Get-CIPPTable -TableName 'Config'
                    Add-CIPPAzDataTableEntity @ConfigTable -Entity @{
                        PartitionKey = 'CloudBackupDestination'
                        RowKey       = $DestinationId
                        LastTest     = [CIPP.CippJson]::ToJson($LastTest, 5) ?? (ConvertTo-Json -InputObject $LastTest -Depth 5 -Compress)
                        LastTestedAt = [datetime]::UtcNow.ToString('o')
                    } -OperationType 'UpsertMerge'
                    $Summary.TestPassed = $LastTest.Passed
                    if ($LastTest.Passed) {
                        $Step.Message = "Connection test passed (versioning: $($LastTest.Versioning))"
                    } else {
                        $Step.Status = 'Failed'
                        $Step.Message = 'The storage and destination are ready, but the connection test has not passed yet. Access for CIPP can take up to 10 minutes to apply: test the destination again from Destinations.'
                        $Step.Error = $LastTest.Errors -join '; '
                    }
                }
            }
            if ($Step.Status -eq 'Running') { $Step.Status = 'Completed' }
        } catch {
            $Step.Status = 'Failed'
            $Step.Error = "$((Get-CippException -Exception $_).NormalizedError)"
            $Status = 'Failed'
            $JobError = "$($Step.Name): $($Step.Error)"
            $Summary.FailedStep = $Step.Name
        }
        $Step.CompletedAt = [datetime]::UtcNow.ToString('o')
    }
    if ($Status -eq 'Running') { $Status = 'Completed' }

    $Job.Status = $Status
    $Job.Error = $JobError
    $Job.CompletedAt = [datetime]::UtcNow.ToString('o')
    $Job.Steps = [CIPP.CippJson]::ToJson($Steps, 4) ?? (ConvertTo-Json -InputObject $Steps -Depth 4 -Compress)
    $Job.Summary = [CIPP.CippJson]::ToJson($Summary, 3) ?? (ConvertTo-Json -InputObject $Summary -Depth 3 -Compress)
    Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'CloudBackupJobResult'; RowKey = $JobId; Result = $Job.Summary } -Force
    Add-CIPPAzDataTableEntity @Table -Entity $Job -Force

    $Severity = if ($Status -eq 'Completed') { 'Info' } else { 'Error' }
    $Detail = if ($JobError) { ": $JobError" } else { '' }
    Write-LogMessage -API 'CloudBackup' -message "Cloud backup storage $($Summary.StorageAccount) in resource group $($Summary.ResourceGroup): $($Status.ToLower())$Detail" -sev $Severity
}
