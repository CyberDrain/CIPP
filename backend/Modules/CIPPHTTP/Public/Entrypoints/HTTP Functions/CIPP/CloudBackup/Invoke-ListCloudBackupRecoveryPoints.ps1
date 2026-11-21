function Invoke-ListCloudBackupRecoveryPoints {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackup.Read
    .SYNOPSIS
        List the points in time a backed-up mailbox, OneDrive, site, team or chat user can be browsed and restored at
    .DESCRIPTION
        Lists the recovery points (RunStamp and time, newest first) of one mailbox, OneDrive, site, team or chat user in a cloud backup policy. Pass a RunStamp as AsOf to ListCloudBackupItems to browse that point in time. Callers limited to some tenants can only list those tenants.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Cloud backup policy id
    $PolicyId = "$($Request.Query.PolicyId)"
    # Tenant customerId or default domain
    $TenantValue = "$($Request.Query.TenantId)"
    # Workload: exchange, onedrive, sharepoint or teams
    $Workload = "$($Request.Query.Workload)".ToLowerInvariant()
    # Owner id as returned by ListCloudBackupOwners
    $OwnerId = "$($Request.Query.OwnerId)"

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
    if (-not $OwnerId) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = 'OwnerId is required' }
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

        $Source = Get-CIPPCloudBackupOwnerSource -PolicyId $PolicyId -TenantId $TenantId -Workload $Workload -OwnerId $OwnerId
        $Points = @(Get-CIPPCloudBackupRecoveryPoint -Destination $Source.Destination -OwnerPrefix $Source.OwnerPrefix)
        $Body = foreach ($Point in $Points) {
            [pscustomobject]@{
                RunStamp = "$($Point.RunStamp)"
                At       = if ($Point.At -is [datetime]) { $Point.At.ToUniversalTime().ToString('o') } else { "$($Point.At)" }
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to list cloud backup recovery points: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = @{ Results = "Failed to list cloud backup recovery points: $($ErrorMessage.NormalizedError)" }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Body)
        })
}
