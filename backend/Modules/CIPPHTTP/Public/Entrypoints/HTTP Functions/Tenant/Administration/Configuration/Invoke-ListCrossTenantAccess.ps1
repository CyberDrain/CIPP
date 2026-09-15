function Invoke-ListCrossTenantAccess {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Config.Read
    .DESCRIPTION
        Returns the default cross-tenant access policy inbound-trust settings (whether MFA,
        compliant-device and hybrid-joined claims from other Entra tenants are trusted).
        Read live from Graph, flattened for the Configuration UI.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Tenant = $Request.Query.tenantFilter
    $Policy = New-GraphGetRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/v1.0/policies/crossTenantAccessPolicy/default' -AsApp $true
    $Trust = $Policy.inboundTrust

    $Flat = [PSCustomObject]@{
        isMfaAccepted                       = $Trust.isMfaAccepted
        isCompliantDeviceAccepted           = $Trust.isCompliantDeviceAccepted
        isHybridAzureADJoinedDeviceAccepted = $Trust.isHybridAzureADJoinedDeviceAccepted
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Flat)
        })
}
