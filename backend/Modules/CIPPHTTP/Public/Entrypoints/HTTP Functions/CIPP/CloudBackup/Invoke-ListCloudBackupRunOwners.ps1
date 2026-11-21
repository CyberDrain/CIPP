function Invoke-ListCloudBackupRunOwners {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackup.Read
    .SYNOPSIS
        List the per-mailbox, per-OneDrive, per-site, per-team or per-chat-user results of a cloud backup run
    .DESCRIPTION
        Lists what one cloud backup run did for each mailbox, OneDrive, site, team or chat user it covered: status, items and bytes backed up, items deleted in the source, warnings and the error when it failed. Callers limited to some tenants can only read runs of those tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Run id as returned by ListCloudBackupRuns (Id)
    $RunId = "$($Request.Query.RunId)"

    if ($RunId -notmatch "^([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})_(\d{19}_[^'/\\#?]+)`$") {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'RunId must be a run id from ListCloudBackupRuns' }
            })
    }
    $PolicyId = $Matches[1]
    $RowKey = $Matches[2]

    try {
        $RunsTable = Get-CIPPTable -TableName 'CloudBackupRuns'
        $Run = @(Get-CIPPAzDataTableEntity @RunsTable -Filter "PartitionKey eq '$PolicyId' and RowKey eq '$RowKey'" -Property PartitionKey, RowKey, TenantId)[0]
        if (-not $Run) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::NotFound
                    Body       = @{ Results = "Run $RunId was not found" }
                })
        }
        $AllowedTenants = @(Test-CIPPAccess -Request $Request -TenantList)
        if ($AllowedTenants -notcontains 'AllTenants' -and $AllowedTenants -notcontains $Run.TenantId) {
            return ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::Forbidden
                    Body       = @{ Results = 'You do not have access to the tenant of this run' }
                })
        }

        $OwnersTable = Get-CIPPTable -TableName 'CloudBackupRunOwners'
        $Body = foreach ($Row in @(Get-CIPPAzDataTableEntity @OwnersTable -Filter "PartitionKey eq '$RunId'")) {
            [pscustomobject]@{
                OwnerId           = $Row.OwnerId ?? $Row.RowKey
                OwnerType         = $Row.OwnerType
                DisplayName       = $Row.DisplayName
                UserPrincipalName = if ($Row.UserPrincipalName) { $Row.UserPrincipalName } else { $null }
                SiteUrl           = if ($Row.SiteUrl) { $Row.SiteUrl } else { $null }
                Status            = $Row.Status
                Items             = [int64]$Row.Items
                Bytes             = [int64]$Row.Bytes
                Deleted           = [int64]$Row.Deleted
                WarningCount      = [int]$Row.WarningCount
                Warnings          = @(if ($Row.Warnings) { [CIPP.CippJson]::ConvertFromJson([string]$Row.Warnings) })
                Error             = if ($Row.Error) { $Row.Error } else { $null }
                StartedAt         = if ($Row.StartedAt) { "$($Row.StartedAt)" } else { $null }
                CompletedAt       = if ($Row.CompletedAt) { "$($Row.CompletedAt)" } else { $null }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to list cloud backup run results: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = @{ Results = "Failed to list cloud backup run results: $($ErrorMessage.NormalizedError)" }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Body)
        })
}
