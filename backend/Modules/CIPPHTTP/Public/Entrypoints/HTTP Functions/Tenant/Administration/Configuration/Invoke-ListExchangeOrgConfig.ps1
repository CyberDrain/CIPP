function Invoke-ListExchangeOrgConfig {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Config.Read
    .DESCRIPTION
        Returns tenant-wide Exchange Online organization settings (Get-OrganizationConfig).
        Read live so values are always current before a change.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Tenant = $Request.Query.tenantFilter
    $Select = 'BookingsEnabled,MessageRecallEnabled,FocusedInboxOn,SendFromAliasEnabled,OnlineMeetingsByDefaultEnabled,TwoClickMailPreviewEnabled,EwsEnabled,AuditDisabled,CustomerLockboxEnabled,AppsForOfficeEnabled,OAuth2ClientProfileEnabled,ConnectorsEnabled,LinkPreviewEnabled,ReadTrackingEnabled,PublicComputersDetectionEnabled,SmtpActionableMessagesEnabled,OutlookPayEnabled'

    $Config = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OrganizationConfig' -Select $Select

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Config)
        })
}
