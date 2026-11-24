function Set-CIPPDBCacheRoles {
    <#
    .SYNOPSIS
        Caches all directory roles and their members for a tenant

    .PARAMETER TenantFilter
        The tenant to cache role data for

    .PARAMETER QueueId
        The queue ID to update with total tasks (optional)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantFilter,
        [string]$QueueId
    )

    try {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Caching directory roles' -sev Debug

        $Roles = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/directoryRoles' -tenantid $TenantFilter

        # Build bulk request for role members
        $MemberRequests = $Roles | ForEach-Object {
            if ($_.id) {
                [PSCustomObject]@{
                    id     = $_.id
                    method = 'GET'
                    url    = "/directoryRoles/$($_.id)/members?`$select=id,displayName,userPrincipalName,appId"
                }
            }
        }

        if ($MemberRequests) {
            Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Fetching role members' -sev Debug
            $MemberResults = New-GraphBulkRequest -Requests @($MemberRequests) -tenantid $TenantFilter

            # A failed or partial member read throws before anything is written, so the old cached rows stay
            $MembersByRoleId = @{}
            foreach ($Result in $MemberResults) {
                if (($Result.status -as [int]) -ge 400 -or $Result.PagingIncomplete) {
                    throw "Member request for role $($Result.id) failed: $($Result.body.error.message ?? $Result.PagingError ?? $Result.status)"
                }
                $MembersByRoleId[[string]$Result.id] = $Result.body.value
            }

            # Add members to each role object
            $RolesWithMembers = foreach ($Role in $Roles) {
                $Members = $MembersByRoleId[[string]$Role.id]
                [PSCustomObject]@{
                    id             = $Role.id
                    displayName    = $Role.displayName
                    description    = $Role.description
                    roleTemplateId = $Role.roleTemplateId
                    members        = $Members
                    memberCount    = ($Members | Measure-Object).Count
                }
            }

            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Roles' -Data $RolesWithMembers -AddCount
            $Roles = $null
            $RolesWithMembers = $null
        } else {
            Add-CIPPDbItem -TenantFilter $TenantFilter -Type 'Roles' -Data $Roles -AddCount
            $Roles = $null
        }

        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message 'Cached directory roles successfully' -sev Debug

    } catch {
        Write-LogMessage -API 'CIPPDBCache' -tenant $TenantFilter -message "Failed to cache directory roles: $($_.Exception.Message)" -sev Error
    }
}
