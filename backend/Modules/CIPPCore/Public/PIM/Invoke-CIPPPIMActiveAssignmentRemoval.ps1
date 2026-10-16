function Invoke-CIPPPIMActiveAssignmentRemoval {
    <#
    .NOTES
        Permission: Graph | GET /roleManagement/directory/roleAssignments | Delegated | RoleManagement.Read.Directory | EntitlementManagement.ReadWrite.All
        Permission: Graph | DELETE /roleManagement/directory/roleAssignments/{id} | Delegated | RoleManagement.ReadWrite.Directory
        Permission: Graph | GET /roleManagement/directory/roleAssignmentScheduleInstances | Application | RoleAssignmentSchedule.Read.Directory | RoleAssignmentSchedule.ReadWrite.Directory, RoleManagement.Read.All, RoleManagement.Read.Directory, RoleManagement.ReadWrite.Directory
    #>
    param(
        [string]$TenantFilter,
        [string]$PrincipalId,
        [string]$RoleDefinitionId,
        [string]$DirectoryScopeId,
        [string]$Justification,
        [string]$PrincipalLabel,
        [string]$RoleName
    )

    # adminRemove covers PIM-created and legacy direct assignments alike; the unified RBAC
    # delete is only a fallback for the rare record PIM does not recognise.
    $Request = New-CIPPPIMScheduleRequest -Kind Assignment -Action adminRemove -PrincipalId $PrincipalId -RoleDefinitionId $RoleDefinitionId -DirectoryScopeId $DirectoryScopeId -Justification $Justification
    try {
        $null = Send-CIPPPIMScheduleRequest -Request $Request -TenantFilter $TenantFilter
    } catch {
        # Entra refuses to retire an active assignment younger than five minutes
        # ("The Active duration is too short. Minimum Required is 5 minutes").
        if ($_.Exception.Message -match 'duration is too short') {
            throw [System.ArgumentException]::new("Entra requires an active assignment to exist for at least 5 minutes before it can be removed; $PrincipalLabel's $RoleName assignment was created too recently. Try again in a few minutes.")
        }
        if ($_.Exception.Message -notmatch 'RoleAssignmentDoesNotExist|does not exist|NotFound|not found') { throw }
        $Existing = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments?`$filter=principalId eq '$PrincipalId' and roleDefinitionId eq '$RoleDefinitionId'" -tenantid $TenantFilter | Where-Object { ($_.directoryScopeId ?? '/') -eq $DirectoryScopeId })
        if ($Existing.Count -eq 0) { throw }
        foreach ($Assignment in $Existing) {
            $null = New-GraphPOSTRequest -type DELETE -uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments/$($Assignment.id)" -tenantid $TenantFilter
        }
    }
    # Graph accepts the removal (status Revoked) and retires the instance a few seconds later;
    # wait for that so the reported state - and the table refresh behind it - is the real one.
    for ($Attempt = 0; $Attempt -lt 8; $Attempt++) {
        $Remaining = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignmentScheduleInstances?`$filter=principalId eq '$PrincipalId' and roleDefinitionId eq '$RoleDefinitionId'" -tenantid $TenantFilter -AsApp $true | Where-Object { ($_.directoryScopeId ?? '/') -eq $DirectoryScopeId })
        if ($Remaining.Count -eq 0) { return $true }
        Start-Sleep -Seconds 3
    }
    return $false
}
