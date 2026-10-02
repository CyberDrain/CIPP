function Invoke-ListEntraAuthPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Config.Read
    .DESCRIPTION
        Returns the Entra authorization policy settings (guest invite scope, SSPR, and the
        default-user-role permissions) flattened for the Configuration UI. Read live from Graph.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Tenant = $Request.Query.tenantFilter
    $Policy = New-GraphGetRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/authorizationPolicy/authorizationPolicy' -AsApp $true
    $Defaults = $Policy.defaultUserRolePermissions

    # Flatten defaultUserRolePermissions.* to top level so the UI binds simple fields.
    $Flat = [PSCustomObject]@{
        allowInvitesFrom                         = $Policy.allowInvitesFrom
        allowedToUseSSPR                         = $Policy.allowedToUseSSPR
        guestUserRoleId                          = $Policy.guestUserRoleId
        blockMsolPowerShell                      = $Policy.blockMsolPowerShell
        allowedToCreateApps                      = $Defaults.allowedToCreateApps
        allowedToCreateSecurityGroups            = $Defaults.allowedToCreateSecurityGroups
        allowedToCreateTenants                   = $Defaults.allowedToCreateTenants
        allowedToReadBitLockerKeysForOwnedDevice = $Defaults.allowedToReadBitLockerKeysForOwnedDevice
        allowedToReadOtherUsers                  = $Defaults.allowedToReadOtherUsers
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Flat)
        })
}
