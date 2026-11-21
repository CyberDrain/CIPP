function Invoke-ListCloudBackupDestinations {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.Read
    .SYNOPSIS
        List cloud backup destinations
    .DESCRIPTION
        Lists the storage destinations (Azure Blob, Amazon S3 or S3-compatible) that cloud backup policies upload to, with the last connection test result and how many policies use each one. Secrets are never returned.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Optional destination id to return a single destination
    $Id = $Request.Query.Id
    if ($Id -and -not ($Id -as [guid])) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Id must be a destination id (GUID)' }
            })
    }

    try {
        $Destinations = @(if ($Id) { Get-CIPPCloudBackupDestination -Id $Id } else { Get-CIPPCloudBackupDestination })
        if ($Id -and $Destinations.Count -eq 0) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Results = "Destination $Id was not found" }
                })
        }

        $PolicyCounts = @{}
        foreach ($Policy in @(Get-CIPPCloudBackupPolicy)) { $PolicyCounts["$($Policy.DestinationId)"]++ }

        $Body = foreach ($Destination in $Destinations) {
            $DestinationId = "$($Destination.RowKey ?? $Destination.Id)"
            $Region = if ($Destination.Region) { $Destination.Region } else { 'us-east-1' }
            $Location = if ($Destination.Provider -eq 'AzureBlob') {
                "$($Destination.StorageAccount)/$($Destination.Container)"
            } elseif ($Destination.Endpoint) {
                $EndpointUri = $null
                $EndpointText = if ($Destination.Endpoint -match '^[a-z][a-z0-9+.-]*://') { $Destination.Endpoint } else { "https://$($Destination.Endpoint)" }
                $EndpointHost = if ([uri]::TryCreate($EndpointText, [System.UriKind]::Absolute, [ref]$EndpointUri)) { $EndpointUri.Host } else { $Destination.Endpoint }
                "$($Destination.Bucket) @ $EndpointHost"
            } else {
                "$($Destination.Bucket) ($Region)"
            }
            $LastTest = $Destination.LastTest
            if ($LastTest -is [string]) { $LastTest = if ($LastTest) { [CIPP.CippJson]::ConvertFromJson($LastTest) } else { $null } }
            $LastTestStatus = if ($null -eq $LastTest) { $null } elseif ($LastTest.Passed -eq $true) { 'Passed' } else { 'Failed' }

            [pscustomobject]@{
                Id             = $DestinationId
                Name           = $Destination.Name
                Provider       = $Destination.Provider
                Location       = $Location
                StorageAccount = $Destination.StorageAccount
                Container      = $Destination.Container
                SubscriptionId = $Destination.SubscriptionId
                ResourceGroup  = $Destination.ResourceGroup
                AzureTenantId  = $Destination.AzureTenantId
                ClientId       = $Destination.ClientId
                Endpoint       = $Destination.Endpoint
                Region         = $Destination.Region
                Bucket         = $Destination.Bucket
                AccessKeyId    = $Destination.AccessKeyId
                ForcePathStyle = "$($Destination.ForcePathStyle)" -eq 'True'
                SecretSet      = if ($Destination.AuthMode -ne 'CippApp' -and (Get-CIPPSecret -Name "CloudBackupDest-$DestinationId")) { 'SentToKeyVault' } else { $null }
                AuthMode       = $Destination.AuthMode
                ProvisionedBy  = $Destination.ProvisionedBy
                ImmutabilityDays = $Destination.ImmutabilityDays
                LastTestedAt   = if ($Destination.LastTestedAt) { "$($Destination.LastTestedAt)" } else { $null }
                LastTestStatus = $LastTestStatus
                LastTest       = if ($null -eq $LastTest) { $null } else {
                    [pscustomobject]@{
                        Write         = $LastTest.Write
                        Read          = $LastTest.Read
                        Delete        = $LastTest.Delete
                        Lifecycle     = $LastTest.Lifecycle
                        Versioning    = $LastTest.Versioning
                        ContentReady  = $LastTest.ContentReady -eq $true
                        VersionDelete = $LastTest.VersionDelete
                        Errors        = @($LastTest.Errors).Where({ $_ })
                    }
                }
                PolicyCount    = [int]$PolicyCounts[$DestinationId]
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to list cloud backup destinations: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $Body = @{ Results = "Failed to list cloud backup destinations: $($ErrorMessage.NormalizedError)" }
        return ([HttpResponseContext]@{ StatusCode = $StatusCode; Body = $Body })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Body)
        })
}
