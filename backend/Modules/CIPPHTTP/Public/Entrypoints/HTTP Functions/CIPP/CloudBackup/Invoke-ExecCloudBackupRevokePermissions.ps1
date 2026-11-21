function Invoke-ExecCloudBackupRevokePermissions {
    <#
    .FUNCTIONALITY
        Entrypoint,AnyTenant
    .ROLE
        CIPP.CloudBackup.ReadWrite
    .SYNOPSIS
        Revoke cloud backup permissions in a tenant
    .DESCRIPTION
        Removes the Microsoft Graph application permissions cloud backup granted CIPP's app in a tenant that no cloud backup policy backs up any more. Permissions that are part of CIPP's own permission set, or that the app had before cloud backup granted them, are kept.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Headers = $Request.Headers
    # customerId or default domain of the tenant
    $TenantValue = "$($Request.Body.TenantId.value ?? $Request.Body.TenantId)"

    if (-not $TenantValue -or $TenantValue -eq 'AllTenants' -or $TenantValue -like 'group:*') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'TenantId must be a single tenant' } })
    }

    try {
        $Tenant = (Get-CIPPTenantLookup)[$TenantValue]
        if (-not $Tenant) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::NotFound; Body = @{ Results = "Tenant $TenantValue was not found" } })
        }
        $AllowedTenants = @(Test-CIPPAccess -Request $Request -TenantList)
        if ($AllowedTenants -notcontains 'AllTenants' -and $AllowedTenants -notcontains $Tenant.customerId) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Forbidden; Body = @{ Results = "You do not have access to $($Tenant.defaultDomainName)" } })
        }

        $Table = Get-CIPPTable -TableName 'CloudBackupPermissions'
        $Record = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'GrantedRoles' and RowKey eq '$($Tenant.customerId)'" -Property PartitionKey, RowKey)[0]
        if (-not $Record) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "Cloud backup has not granted any permissions in $($Tenant.defaultDomainName)" } })
        }
        $Unused = @(Get-CIPPCloudBackupUnusedPermission -TenantId $Tenant.customerId)[0]
        if (-not $Unused) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "A cloud backup policy still backs up $($Tenant.defaultDomainName). Remove it from every policy first." } })
        }

        $Failed = [System.Collections.Generic.List[string]]::new()
        $Removed = 0
        if ($Unused.RoleIds.Count -gt 0) {
            $Revoke = [System.Collections.Generic.HashSet[string]]::new([string[]]$Unused.RoleIds, [StringComparer]::OrdinalIgnoreCase)
            $ServicePrincipal = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$($env:ApplicationID)')?`$select=id" -tenantid $Tenant.customerId -skipTokenCache $true -NoAuthCheck $true
            $Assignments = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($ServicePrincipal.id)/appRoleAssignments?`$select=id,appRoleId" -tenantid $Tenant.customerId -skipTokenCache $true -NoAuthCheck $true)
            $RoleById = @{}
            $Requests = [System.Collections.Generic.List[object]]::new()
            foreach ($Assignment in $Assignments) {
                if (-not $Revoke.Contains("$($Assignment.appRoleId)")) { continue }
                $RequestId = "$($Requests.Count + 1)"
                $RoleById[$RequestId] = "$($Assignment.appRoleId)"
                $Requests.Add(@{ id = $RequestId; method = 'DELETE'; url = "/servicePrincipals/$($ServicePrincipal.id)/appRoleAssignments/$($Assignment.id)" })
            }
            if ($Requests.Count -gt 0) {
                foreach ($Result in @(New-GraphBulkRequest -Requests @($Requests) -tenantid $Tenant.customerId -NoAuthCheck $true)) {
                    if ([int]$Result.status -ge 200 -and [int]$Result.status -lt 300) { $Removed++ } else { $Failed.Add($RoleById["$($Result.id)"]) }
                }
                if ($Removed -gt 0) { $null = Clear-CippTokenCache -TenantFilter $Tenant.customerId }
            }
        }

        if ($Failed.Count -eq 0) {
            Remove-CIPPAzDataTableEntity @Table -Entity $Record -Force
        } else {
            $FailedIds = [string[]]@($Failed)
            Add-CIPPAzDataTableEntity @Table -Entity @{
                PartitionKey = 'GrantedRoles'
                RowKey       = $Tenant.customerId
                RoleIds      = [CIPP.CippJson]::ToJson($FailedIds, 2) ?? (ConvertTo-Json -InputObject $FailedIds -Compress)
            } -OperationType 'UpsertMerge'
        }

        $Names = @{}
        foreach ($Role in Get-CIPPCloudBackupPermissionRole) { $Names[$Role.Id] = $Role.Name }
        $Result = if ($Failed.Count -gt 0) {
            "Revoked $Removed cloud backup $(if ($Removed -eq 1) { 'permission' } else { 'permissions' }) in $($Tenant.defaultDomainName). Could not revoke: $(@(foreach ($Id in $Failed) { $Names[$Id] ?? $Id }) -join ', '). Try again."
        } elseif ($Removed -gt 0) {
            "Revoked $Removed cloud backup $(if ($Removed -eq 1) { 'permission' } else { 'permissions' }) in $($Tenant.defaultDomainName)."
        } else {
            "No cloud backup permissions were left to revoke in $($Tenant.defaultDomainName)."
        }
        Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -tenant $Tenant.defaultDomainName -tenantid $Tenant.customerId -message $Result -sev $(if ($Failed.Count -gt 0) { 'Warning' } else { 'Info' })
        $StatusCode = Get-CippBulkStatusCode -Total ($Removed + $Failed.Count) -Failed $Failed.Count
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Result = "Failed to revoke cloud backup permissions in $($TenantValue): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $Request.Params.CIPPEndpoint -message $Result -sev Error -LogData $ErrorMessage
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Result }
        })
}
