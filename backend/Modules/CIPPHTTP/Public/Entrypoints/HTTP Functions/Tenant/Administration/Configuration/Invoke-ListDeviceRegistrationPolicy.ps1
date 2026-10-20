function Invoke-ListDeviceRegistrationPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Config.Read
    .DESCRIPTION
        Returns the Entra device registration policy settings surfaced here (Windows LAPS and the
        per-user device quota), flattened for the Configuration UI. Read live from Graph.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Tenant = $Request.Query.tenantFilter
    $Policy = New-GraphGetRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/policies/deviceRegistrationPolicy' -AsApp $true

    $Flat = [PSCustomObject]@{
        lapsEnabled     = $Policy.localAdminPassword.isEnabled
        userDeviceQuota = $Policy.userDeviceQuota
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Flat)
        })
}
