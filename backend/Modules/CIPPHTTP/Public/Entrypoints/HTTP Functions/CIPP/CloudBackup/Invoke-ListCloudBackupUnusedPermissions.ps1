function Invoke-ListCloudBackupUnusedPermissions {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackup.Read
    .SYNOPSIS
        List cloud backup permissions that no policy needs
    .DESCRIPTION
        Lists tenants where cloud backup granted CIPP's app Microsoft Graph permissions but no cloud backup policy backs the tenant up any more, with the permissions a revoke would remove. Permissions that are part of CIPP's own permission set, or that the app had before cloud backup granted them, are kept and not listed. With a tenant, only that tenant.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    # Optional tenant (default domain or customerId) to list
    $TenantFilter = $Request.Query.tenantFilter
    if ($TenantFilter -eq 'AllTenants') { $TenantFilter = $null }

    try {
        $AllowedTenants = @(Test-CIPPAccess -Request $Request -TenantList)
        $AllAllowed = $AllowedTenants -contains 'AllTenants'
        $Lookup = Get-CIPPTenantLookup
        $SelectedId = $null
        if ($TenantFilter) {
            $SelectedId = $Lookup["$TenantFilter"].customerId
            if (-not $SelectedId) {
                return ([HttpResponseContext]@{
                        StatusCode = [HttpStatusCode]::NotFound
                        Body       = @{ Results = "Tenant $TenantFilter was not found" }
                    })
            }
        }

        $Body = foreach ($Entry in @(Get-CIPPCloudBackupUnusedPermission -TenantId $SelectedId)) {
            if ($Entry.RoleIds.Count -eq 0) { continue }
            if (-not $AllAllowed -and $AllowedTenants -notcontains $Entry.TenantId) { continue }
            [pscustomobject]@{
                TenantId    = $Entry.TenantId
                Tenant      = $Lookup[$Entry.TenantId].defaultDomainName ?? $Entry.TenantId
                Permissions = @($Entry.Permissions)
                GrantedAt   = $Entry.GrantedAt
            }
        }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to list unused cloud backup permissions: $($ErrorMessage.NormalizedError)" -sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{
                StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
                Body       = @{ Results = "Failed to list unused cloud backup permissions: $($ErrorMessage.NormalizedError)" }
            })
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @($Body)
        })
}
