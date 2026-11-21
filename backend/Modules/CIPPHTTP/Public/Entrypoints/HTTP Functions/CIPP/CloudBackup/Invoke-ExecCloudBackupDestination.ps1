function Invoke-ExecCloudBackupDestination {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    .SYNOPSIS
        Add, edit, delete or test a cloud backup destination
    .DESCRIPTION
        Saves an Azure Blob, Amazon S3 or S3-compatible destination for cloud backups and runs a connection test (write, read, delete, lifecycle rules, versioning). The client secret or secret access key is stored in Key Vault; send 'SentToKeyVault' or leave it blank on Edit to keep the stored secret. An Azure Blob destination with AuthMode CippApp signs in as CIPP's own app and needs no client id or secret. Delete is refused while a policy uses the destination.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Headers = $Request.Headers
    $Action = $Request.Body.Action
    $Id = $Request.Body.Id
    $Name = "$($Request.Body.Name)".Trim()
    $Provider = $Request.Body.Provider.value ?? $Request.Body.Provider
    # Azure Blob sign-in: ServicePrincipal (client id and secret, the default) or CippApp (CIPP's own app, no secret); Edit keeps the stored mode when blank
    $AuthModeInput = "$($Request.Body.AuthMode.value ?? $Request.Body.AuthMode)".Trim()

    if ($Action -notin @('Add', 'Edit', 'Delete', 'Test')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Action must be Add, Edit, Delete or Test' }
            })
    }
    if ($Action -ne 'Add' -and -not ($Id -as [guid])) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Id must be a destination id (GUID)' }
            })
    }
    if ($AuthModeInput -and $AuthModeInput -notin @('ServicePrincipal', 'CippApp')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'AuthMode must be ServicePrincipal or CippApp' }
            })
    }
    $AuthMode = if ($AuthModeInput) { $AuthModeInput } else { 'ServicePrincipal' }
    $AuthModeKnown = $Action -eq 'Add' -or [bool]$AuthModeInput

    $Fields = @{
        StorageAccount = "$($Request.Body.StorageAccount)".Trim()
        Container      = "$($Request.Body.Container)".Trim()
        SubscriptionId = "$($Request.Body.SubscriptionId)".Trim()
        ResourceGroup  = "$($Request.Body.ResourceGroup)".Trim()
        AzureTenantId  = "$($Request.Body.AzureTenantId)".Trim()
        ClientId       = "$($Request.Body.ClientId)".Trim()
        Endpoint       = "$($Request.Body.Endpoint)".Trim()
        Region         = "$($Request.Body.Region)".Trim()
        Bucket         = "$($Request.Body.Bucket)".Trim()
        AccessKeyId    = "$($Request.Body.AccessKeyId)".Trim()
    }
    $SecretInput = if ($Provider -eq 'AzureBlob') { $Request.Body.ClientSecret } else { $Request.Body.SecretAccessKey }
    $NewSecret = -not [string]::IsNullOrWhiteSpace($SecretInput) -and $SecretInput -ne 'SentToKeyVault'

    if ($Action -in @('Add', 'Edit')) {
        if (-not $Name) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = 'Name is required' }
                })
        }
        if ($Provider -notin @('AzureBlob', 'S3')) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = 'Provider must be AzureBlob or S3' }
                })
        }
        $Required = if ($Provider -eq 'AzureBlob' -and ($AuthMode -eq 'CippApp' -or -not $AuthModeKnown)) {
            @('StorageAccount', 'Container', 'SubscriptionId', 'ResourceGroup')
        } elseif ($Provider -eq 'AzureBlob') {
            @('StorageAccount', 'Container', 'SubscriptionId', 'ResourceGroup', 'AzureTenantId', 'ClientId')
        } else {
            @('Bucket', 'AccessKeyId')
        }
        $Missing = @($Required.Where({ -not $Fields[$_] }))
        if ($Action -eq 'Add' -and -not $NewSecret -and -not ($Provider -eq 'AzureBlob' -and $AuthMode -eq 'CippApp')) { $Missing = @($Missing; $(if ($Provider -eq 'AzureBlob') { 'ClientSecret' } else { 'SecretAccessKey' })) }
        if ($Missing.Count -gt 0) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Missing required fields: $($Missing -join ', ')" }
                })
        }
        if ($Provider -eq 'AzureBlob' -and $Fields.StorageAccount -cnotmatch '^[a-z0-9]{3,24}$') {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = 'StorageAccount must be 3 to 24 lowercase letters and numbers' }
                })
        }
        $EndpointUri = $null
        if ($Provider -eq 'S3' -and $Fields.Endpoint -and -not ([uri]::TryCreate($Fields.Endpoint, [System.UriKind]::Absolute, [ref]$EndpointUri) -and $EndpointUri.Scheme -in @('http', 'https'))) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = 'Endpoint must be a full http(s) URL, or blank for Amazon S3' }
                })
        }
    }

    $Results = [System.Collections.Generic.List[object]]::new()
    try {
        $Table = Get-CIPPTable -TableName 'Config'
        $Existing = $null
        if ($Action -ne 'Add') {
            $Existing = Get-CIPPCloudBackupDestination -Id $Id
            if (-not $Existing) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body       = @{ Results = "Destination $Id was not found" }
                    })
            }
        }

        if ($Action -eq 'Delete') {
            $UsedBy = @(@(Get-CIPPCloudBackupPolicy).Where({ $_.DestinationId -eq $Id }))
            if ($UsedBy.Count -gt 0) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ Results = "Destination $($Existing.Name) is used by: $($UsedBy.Name -join ', '). Move or delete those policies first." }
                    })
            }
            Remove-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'CloudBackupDestination'; RowKey = "$Id" } -Force
            Remove-CIPPSecret -Name "CloudBackupDest-$Id"
            Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message "Deleted cloud backup destination $($Existing.Name)" -sev Info
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = @{ Results = @(@{ resultText = "Deleted destination $($Existing.Name)"; state = 'success' }) }
                })
        }

        if ($Action -in @('Add', 'Edit')) {
            if ($Action -eq 'Add') { $Id = [guid]::NewGuid().ToString() }
            if ($Action -eq 'Edit' -and $Existing.Provider -ne $Provider) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::BadRequest
                        Body       = @{ Results = 'The provider of a destination cannot be changed. Add a new destination instead.' }
                    })
            }
            $IsAzure = $Provider -eq 'AzureBlob'
            if ($IsAzure -and -not $AuthModeKnown -and $Existing.AuthMode -eq 'CippApp') { $AuthMode = 'CippApp' }
            $IsCippApp = $IsAzure -and $AuthMode -eq 'CippApp'
            if ($IsAzure -and -not $IsCippApp) {
                $Missing = @(@('AzureTenantId', 'ClientId').Where({ -not $Fields[$_] }))
                if ($Existing.AuthMode -eq 'CippApp' -and -not $NewSecret) { $Missing = @($Missing; 'ClientSecret') }
                if ($Missing.Count -gt 0) {
                    return ([HttpResponseContext]@{
                            StatusCode = [HttpStatusCode]::BadRequest
                            Body       = @{ Results = "Missing required fields: $($Missing -join ', ')" }
                        })
                }
            }
            $Entity = @{
                PartitionKey   = 'CloudBackupDestination'
                RowKey         = "$Id"
                Name           = $Name
                Provider       = $Provider
                StorageAccount = if ($IsAzure) { $Fields.StorageAccount } else { '' }
                Container      = if ($IsAzure) { $Fields.Container } else { '' }
                SubscriptionId = if ($IsAzure) { $Fields.SubscriptionId } else { '' }
                ResourceGroup  = if ($IsAzure) { $Fields.ResourceGroup } else { '' }
                AzureTenantId  = if ($IsCippApp) { "$($env:TenantID)" } elseif ($IsAzure) { $Fields.AzureTenantId } else { '' }
                ClientId       = if ($IsCippApp) { "$($env:ApplicationID)" } elseif ($IsAzure) { $Fields.ClientId } else { '' }
                AuthMode       = if ($IsAzure) { $AuthMode } else { '' }
                ProvisionedBy  = "$($Existing.ProvisionedBy)"
                ImmutabilityDays = ($Existing.ImmutabilityDays -as [int]) ?? 0
                Endpoint       = if ($IsAzure) { '' } else { $Fields.Endpoint }
                Region         = if ($IsAzure) { '' } else { $Fields.Region }
                Bucket         = if ($IsAzure) { '' } else { $Fields.Bucket }
                AccessKeyId    = if ($IsAzure) { '' } else { $Fields.AccessKeyId }
                ForcePathStyle = (-not $IsAzure) -and $Request.Body.ForcePathStyle -eq $true
                LastTest       = ''
                LastTestedAt   = ''
            }
            if ($NewSecret -and -not $IsCippApp) { Set-CIPPSecret -Name "CloudBackupDest-$Id" -Value $SecretInput }
            Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
            Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message "Saved cloud backup destination $Name ($Provider)" -sev Info
            $Results.Add(@{ resultText = "Saved destination $Name"; state = 'success' })
        }

        $Destination = Get-CIPPCloudBackupDestination -Id $Id -IncludeSecret
        $DestinationName = $Destination.Name ?? $Name
        try {
            $Test = Test-CIPPCloudBackupDestination -Destination $Destination
        } catch {
            $Test = [pscustomobject]@{
                Write      = $false
                Read       = $false
                Delete     = $false
                Lifecycle  = $false
                Versioning = $null
                Passed     = $false
                Errors     = @((Get-CippException -Exception $_).NormalizedError)
            }
        }
        $LastTest = [ordered]@{
            Write      = [bool]$Test.Write
            Read       = [bool]$Test.Read
            Delete     = [bool]$Test.Delete
            Lifecycle  = [bool]$Test.Lifecycle
            Versioning    = $Test.Versioning
            VersionDelete = [bool]$Test.VersionDelete
            ContentReady  = [bool]$Test.ContentReady
            Passed        = [bool]$Test.Passed
            Errors        = @(@($Test.Errors).Where({ $_ }))
        }
        $LastTestJson = [CIPP.CippJson]::ToJson($LastTest, 5) ?? (ConvertTo-Json -InputObject $LastTest -Depth 5 -Compress)
        Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'CloudBackupDestination'; RowKey = "$Id"; LastTest = $LastTestJson; LastTestedAt = [datetime]::UtcNow.ToString('o') } -OperationType 'UpsertMerge'

        $FailedChecks = @(foreach ($Check in 'Write', 'Read', 'Delete', 'Lifecycle') { if (-not $LastTest[$Check]) { $Check } })
        if ($LastTest.Passed) {
            if ($Action -eq 'Test') {
                $Results.Add(@{ resultText = "Connection test passed for $DestinationName (versioning: $($LastTest.Versioning))"; state = 'success' })
            }
            $StatusCode = [HttpStatusCode]::OK
        } else {
            $Messages = if ($LastTest.Errors.Count -gt 0) { $LastTest.Errors } else { @(foreach ($Check in $FailedChecks) { "$Check check failed" }) }
            foreach ($Message in $Messages) { $Results.Add(@{ resultText = "Connection test for ${DestinationName}: $Message"; state = 'error' }) }
            Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message "Connection test failed for cloud backup destination ${DestinationName}: $($Messages -join '; ')" -sev Warning
            $StatusCode = if ($Action -eq 'Test') {
                Get-CippBulkStatusCode -Total 4 -Failed ([Math]::Max(1, $FailedChecks.Count))
            } else {
                [HttpStatusCode]::MultiStatus
            }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to $($Action.ToLower()) cloud backup destination: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message $Message -sev Error -LogData $ErrorMessage
        $Results.Add(@{ resultText = $Message; state = 'error' })
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = @($Results) }
        })
}
