function Invoke-ListTeamsConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Config.Read
    .DESCRIPTION
        Returns a tenant-wide Teams Global policy/configuration object for the Configuration UI.
        The policyType query parameter selects which one (meeting, messaging, client, external
        access). Read live via the Teams admin ConfigAPI.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Tenant = $Request.Query.tenantFilter
    $PolicyType = $Request.Query.policyType
    $Allowed = @('TeamsMeetingPolicy', 'TeamsMessagingPolicy', 'TeamsClientConfiguration', 'ExternalAccessPolicy')

    if ($PolicyType -notin $Allowed) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = "Unsupported policyType '$PolicyType'." }
            })
    }

    $Config = New-TeamsRequestV2 -TenantFilter $Tenant -Type $PolicyType -Action Get -Identity 'Global'

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Config)
        })
}
