function Invoke-ListAdminAuditLogConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Config.Read
    .DESCRIPTION
        Returns the tenant's Exchange Online admin audit log configuration (notably whether the
        Unified Audit Log is enabled). Read live from Exchange Online so the value is always current.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Tenant = $Request.Query.tenantFilter
    $AuditConfig = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-AdminAuditLogConfig'

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($AuditConfig)
        })
}
