function Invoke-ListSpoTenantSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Sharepoint.Admin.Read
    .DESCRIPTION
        Returns the SharePoint Online tenant admin (CSOM) settings - sharing link defaults,
        sync, guest access and related toggles that are not on the Graph sharepoint/settings
        object. Read live (-SkipCache) so values are always current before a change.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Tenant = $Request.Query.tenantFilter

    # One CSOM call hydrates the whole tenant object; project the fields this section renders.
    $Fields = @(
        'DefaultSharingLinkType'
        'DefaultLinkPermission'
        'DisableAddToOneDrive'
        'EnableAzureADB2BIntegration'
        'CustomScriptsRestrictMode'
        'DisableSharePointStoreAccess'
        'DisallowInfectedFileDownload'
        'ShowPeoplePickerSuggestionsForGuestUsers'
        'HideSyncButtonOnDocLib'
        'ConditionalAccessPolicy'
        'ExternalUserExpirationRequired'
        'ExternalUserExpireInDays'
        'EmailAttestationRequired'
        'EmailAttestationReAuthDays'
        'SharingCapability'
    )

    $Settings = Get-CIPPSPOTenant -TenantFilter $Tenant -SkipCache | Select-Object -Property $Fields

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Settings)
        })
}
