function Invoke-ListCloudBackupOwners {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackup.Read
    .SYNOPSIS
        List the backed-up mailboxes, OneDrives, sites, teams or chat users of a tenant in a cloud backup policy
    .DESCRIPTION
        Lists every mailbox, OneDrive, site, team or chat user a cloud backup policy has backed up in one tenant for one workload, including ones that were removed from the tenant or excluded from the policy (Removed, RemovedReason Removed or Excluded, RemovedAt), with when they were last backed up and how many items and bytes were backed up. Callers limited to some tenants can only list those tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Cloud backup policy id
    $PolicyId = "$($Request.Query.PolicyId)"
    # Tenant customerId or default domain
    $TenantValue = "$($Request.Query.TenantId)"
    # Workload: exchange, onedrive, sharepoint or teams
    $Workload = "$($Request.Query.Workload)".ToLowerInvariant()

    if (-not ($PolicyId -as [guid])) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'PolicyId must be a policy id (GUID)' }
            })
    }
    if (-not $TenantValue) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'TenantId is required' }
            })
    }
    if ($Workload -notin @('exchange', 'onedrive', 'sharepoint', 'teams')) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'Workload must be exchange, onedrive, sharepoint or teams' }
            })
    }

    try {
        $TenantId = (Get-CIPPTenantLookup)[$TenantValue].customerId
        if (-not $TenantId) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Results = "Tenant $TenantValue was not found" }
                })
        }
        $AllowedTenants = @(Test-CIPPAccess -Request $Request -TenantList)
        if ($AllowedTenants -notcontains 'AllTenants' -and $AllowedTenants -notcontains $TenantId) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = @{ Results = 'You do not have access to this tenant' }
                })
        }
        $Policy = Get-CIPPCloudBackupPolicy -Id $PolicyId
        if (-not $Policy) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Results = "Cloud backup policy $PolicyId was not found" }
                })
        }

        $StateTable = Get-CIPPTable -TableName 'CloudBackupState'
        $Filter = "PartitionKey eq '$($Policy.Id)_$TenantId' and RowKey ge '$($Workload)_' and RowKey lt '$Workload$([char]0x60)'"
        $Rows = @(Get-CIPPAzDataTableEntity @StateTable -Filter $Filter -Property PartitionKey, RowKey, OwnerId, OwnerType, DisplayName, UserPrincipalName, SiteUrl, Removed, RemovedAt, RemovedReason, LastSuccessAt, Items, Bytes, Status, LastError)
        $Owners = foreach ($Row in $Rows) {
            $Removed = "$($Row.Removed)" -eq 'True'
            [pscustomobject]@{
                OwnerId           = "$($Row.OwnerId ?? $Row.RowKey.Substring($Workload.Length + 1))"
                OwnerType         = "$($Row.OwnerType)"
                DisplayName       = if ($Row.DisplayName) { "$($Row.DisplayName)" } else { "$($Row.OwnerId)" }
                UserPrincipalName = if ($Row.UserPrincipalName) { "$($Row.UserPrincipalName)" } else { $null }
                SiteUrl           = if ($Row.SiteUrl) { "$($Row.SiteUrl)" } else { $null }
                Removed           = $Removed
                RemovedReason     = if ($Removed) { if ("$($Row.RemovedReason)" -eq 'Excluded') { 'Excluded' } else { 'Removed' } } else { $null }
                RemovedAt         = if ($Removed -and $Row.RemovedAt) { "$($Row.RemovedAt)" } else { $null }
                LastSuccessAt     = if ($Row.LastSuccessAt) { "$($Row.LastSuccessAt)" } else { $null }
                Status            = if ($Row.Status) { "$($Row.Status)" } else { $null }
                LastError         = if ($Row.LastError) { "$($Row.LastError)" } else { $null }
                Items             = [int64]($Row.Items -as [int64])
                Bytes             = [int64]($Row.Bytes -as [int64])
            }
        }
        $Body = @($Owners | Sort-Object -Property Removed, DisplayName)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to list cloud backup owners: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = @{ Results = "Failed to list cloud backup owners: $($ErrorMessage.NormalizedError)" }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Body)
        })
}
