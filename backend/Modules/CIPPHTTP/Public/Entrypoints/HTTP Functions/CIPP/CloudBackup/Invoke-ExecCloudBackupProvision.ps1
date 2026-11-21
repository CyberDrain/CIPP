function Invoke-ExecCloudBackupProvision {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.AppSettings.ReadWrite
    .SYNOPSIS
        Create Azure storage for cloud backups and add it as a destination
    .DESCRIPTION
        Starts a background job in which CIPP's managed identity creates a new resource group, a hardened storage account with blob versioning, a private container and optionally a version-level immutability policy, gives CIPP's app access to the account, adds it as a destination and tests it. Follow the job with ListCloudBackupJobs?Id=JobId. Resources are never deleted, also when a step fails.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Headers = $Request.Headers
    $Name = "$($Request.Body.Name)".Trim()
    $SubscriptionId = "$($Request.Body.SubscriptionId.value ?? $Request.Body.SubscriptionId)".Trim()
    # Name of the new resource group; it must not exist yet
    $ResourceGroup = "$($Request.Body.ResourceGroup)".Trim()
    if (-not $ResourceGroup) { $ResourceGroup = 'rg-cipp-cloudbackup' }
    # Azure region name, e.g. westeurope
    $Region = "$($Request.Body.Region.value ?? $Request.Body.Region)".Trim().ToLowerInvariant()
    $Redundancy = "$($Request.Body.Redundancy.value ?? $Request.Body.Redundancy)".Trim()
    if (-not $Redundancy) { $Redundancy = 'Standard_LRS' }
    $Container = "$($Request.Body.Container)".Trim()
    if (-not $Container) { $Container = 'cipp-backups' }
    # Optional version-level immutability period in days (1 to 3650); blank for none
    $ImmutabilityInput = "$($Request.Body.ImmutabilityDays)".Trim()
    $ImmutabilityDays = if ($ImmutabilityInput) { $ImmutabilityInput -as [int] } else { 0 }

    $Problem = if (-not $Name) {
        'Name is required'
    } elseif (-not ($SubscriptionId -as [guid])) {
        'SubscriptionId must be a subscription id (GUID)'
    } elseif ($ResourceGroup -notmatch '^[-\w.()]{0,89}[-\w()]$') {
        'ResourceGroup must be 1 to 90 letters, numbers, underscores, hyphens, periods or parentheses and cannot end with a period'
    } elseif ($Region -notmatch '^[a-z0-9]{2,40}$') {
        'Region is required'
    } elseif ($Redundancy -notin @('Standard_LRS', 'Standard_ZRS', 'Standard_GRS')) {
        'Redundancy must be Standard_LRS, Standard_ZRS or Standard_GRS'
    } elseif ($Container -cnotmatch '^(?!.*--)[a-z0-9][a-z0-9-]{1,61}[a-z0-9]$') {
        'Container must be 3 to 63 lowercase letters, numbers and single hyphens, starting and ending with a letter or number'
    } elseif ($null -eq $ImmutabilityDays -or $ImmutabilityDays -lt 0 -or $ImmutabilityDays -gt 3650 -or ($ImmutabilityInput -and $ImmutabilityDays -eq 0)) {
        'ImmutabilityDays must be a whole number from 1 to 3650, or blank for no immutability'
    }
    if ($Problem) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = $Problem }
            })
    }
    if (-not [System.Environment]::GetEnvironmentVariable('IDENTITY_ENDPOINT') -or -not [System.Environment]::GetEnvironmentVariable('IDENTITY_HEADER')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'CIPP has no managed identity here, so it cannot create storage. Set up the destination manually.' }
            })
    }

    try {
        $Locations = Invoke-CIPPCloudBackupArmRequest -Path "/subscriptions/$SubscriptionId/locations" -ApiVersion '2022-12-01' -AllowStatus 403, 404
        if ($Locations.StatusCode -ge 400) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "CIPP's managed identity cannot use subscription $SubscriptionId. Give it Contributor and User Access Administrator there, or set up the destination manually." }
                })
        }
        if (-not @($Locations.Body.value).Where({ $_.name -eq $Region }, 'First')) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Region $Region is not available in subscription $SubscriptionId" }
                })
        }
        $ExistingGroup = Invoke-CIPPCloudBackupArmRequest -Path "/subscriptions/$SubscriptionId/resourcegroups/$ResourceGroup" -ApiVersion '2024-03-01' -AllowStatus 404
        if ($ExistingGroup.StatusCode -ne 404) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::BadRequest
                    Body       = @{ Results = "Resource group $ResourceGroup already exists. CIPP only creates backup storage in a new resource group; choose another name." }
                })
        }

        $Characters = 'abcdefghijklmnopqrstuvwxyz0123456789'
        $StorageAccount = 'cippbk' + -join @(foreach ($i in 1..18) { $Characters[[System.Security.Cryptography.RandomNumberGenerator]::GetInt32($Characters.Length)] })
        $JobId = [guid]::NewGuid().ToString()
        $Parameters = [ordered]@{
            Name             = $Name
            SubscriptionId   = $SubscriptionId
            ResourceGroup    = $ResourceGroup
            Region           = $Region
            Redundancy       = $Redundancy
            StorageAccount   = $StorageAccount
            Container        = $Container
            ImmutabilityDays = $ImmutabilityDays
            DestinationId    = [guid]::NewGuid().ToString()
        }
        $Now = [datetime]::UtcNow.ToString('o')
        $Table = Get-CIPPTable -TableName 'CloudBackupJobs'
        Add-CIPPAzDataTableEntity @Table -Entity @{
            PartitionKey   = 'CloudBackupJob'
            RowKey         = $JobId
            Type           = 'Provision'
            Status         = 'Queued'
            SourceTenantId = ''
            TargetTenantId = ''
            Parameters     = [CIPP.CippJson]::ToJson($Parameters, 3) ?? (ConvertTo-Json -InputObject $Parameters -Compress)
            Steps          = ''
            RequestedBy    = "$($Headers.'x-ms-client-principal-name')"
            CreatedAt      = $Now
            StartedAt      = ''
            CompletedAt    = ''
            Summary        = ''
            Error          = ''
        } -Force
        $null = Start-CIPPOrchestrator -InputObject ([pscustomobject]@{
                Batch            = @([pscustomobject]@{ FunctionName = 'CloudBackupProvision'; JobId = $JobId })
                OrchestratorName = "CloudBackupProvision_$JobId"
                SkipLog          = $true
            })
        Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message "Started creating cloud backup storage $StorageAccount in resource group $ResourceGroup ($Region)" -sev Info
        $Result = "Creating storage account $StorageAccount in resource group $ResourceGroup. This takes a few minutes."
        $StatusCode = [HttpStatusCode]::Accepted
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to start creating cloud backup storage: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $JobId = $null
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result; JobId = $JobId }
        })
}
