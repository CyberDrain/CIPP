function Remove-CIPPUserOAuthGrant {
    <#
    .SYNOPSIS
        Deletes a user's OAuth consent grants and app-role assignments.
    .DESCRIPTION
        Removes the delegated consent grants (oauth2PermissionGrants) and enterprise-app role
        assignments identified by id. Removing a grant revokes that consent only; it does not disable
        the application for other users (see Set-CIPPServicePrincipalState) and existing access
        tokens keep working until they expire, so pair it with a session revocation.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserId
        The user's object id (needed for app-role assignment deletes).
    .PARAMETER GrantIds
        oauth2PermissionGrant ids to delete.
    .PARAMETER AppRoleAssignmentIds
        appRoleAssignment ids to delete.
    .PARAMETER Headers
        CIPP request headers for logging.
    .PARAMETER APIName
        Logging API name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [string]$UserId,
        [string[]]$GrantIds = @(),
        [string[]]$AppRoleAssignmentIds = @(),
        $Headers,
        [string]$APIName = 'BECRemediate'
    )

    $Results = [System.Collections.Generic.List[object]]::new()
    foreach ($GrantId in @($GrantIds | Where-Object { $_ })) {
        if (-not $PSCmdlet.ShouldProcess($GrantId, 'Delete OAuth consent grant')) { continue }
        try {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants/$GrantId" -tenantid $TenantFilter -type DELETE -AsApp $true
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Deleted OAuth consent grant $GrantId" -Sev 'Info'
            $Results.Add([pscustomobject]@{ Target = $GrantId; state = 'success'; resultText = "Deleted consent grant $GrantId" })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to delete OAuth consent grant $GrantId`: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            $Results.Add([pscustomobject]@{ Target = $GrantId; state = 'error'; resultText = "Failed to delete consent grant $GrantId`: $($ErrorMessage.NormalizedError)" })
        }
    }
    foreach ($AssignmentId in @($AppRoleAssignmentIds | Where-Object { $_ })) {
        if (-not $UserId) {
            $Results.Add([pscustomobject]@{ Target = $AssignmentId; state = 'error'; resultText = 'The user object id is required to remove an app-role assignment' })
            continue
        }
        if (-not $PSCmdlet.ShouldProcess($AssignmentId, 'Delete app-role assignment')) { continue }
        try {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/users/$UserId/appRoleAssignments/$AssignmentId" -tenantid $TenantFilter -type DELETE -AsApp $true
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Deleted app-role assignment $AssignmentId for user $UserId" -Sev 'Info'
            $Results.Add([pscustomobject]@{ Target = $AssignmentId; state = 'success'; resultText = "Deleted app-role assignment $AssignmentId" })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to delete app-role assignment $AssignmentId`: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            $Results.Add([pscustomobject]@{ Target = $AssignmentId; state = 'error'; resultText = "Failed to delete app-role assignment $AssignmentId`: $($ErrorMessage.NormalizedError)" })
        }
    }
    return $Results.ToArray()
}
