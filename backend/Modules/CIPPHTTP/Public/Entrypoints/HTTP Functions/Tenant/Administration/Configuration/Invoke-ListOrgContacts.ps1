function Invoke-ListOrgContacts {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Config.Read
    .DESCRIPTION
        Returns the organization notification contact addresses (marketing, technical and
        security/compliance notification emails). Read live from Graph.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Tenant = $Request.Query.tenantFilter
    $Org = @(New-GraphGetRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/v1.0/organization' -AsApp $true)[0]

    $Flat = [PSCustomObject]@{
        marketingNotificationEmails         = @($Org.marketingNotificationEmails)
        technicalNotificationMails          = @($Org.technicalNotificationMails)
        securityComplianceNotificationMails = @($Org.securityComplianceNotificationMails)
    }

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Flat)
        })
}
