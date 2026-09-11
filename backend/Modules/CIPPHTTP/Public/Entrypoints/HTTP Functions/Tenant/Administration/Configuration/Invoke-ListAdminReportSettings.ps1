function Invoke-ListAdminReportSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Config.Read
    .DESCRIPTION
        Returns the tenant's admin report settings (currently whether usage-report user, group
        and site names are concealed). Read live from Graph so the value is always current.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Tenant = $Request.Query.tenantFilter
    $ReportSettings = New-GraphGetRequest -tenantid $Tenant -Uri 'https://graph.microsoft.com/beta/admin/reportSettings' -AsApp $true

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($ReportSettings)
        })
}
