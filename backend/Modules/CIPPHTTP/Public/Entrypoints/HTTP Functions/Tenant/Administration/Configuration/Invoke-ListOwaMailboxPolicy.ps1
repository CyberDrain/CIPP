function Invoke-ListOwaMailboxPolicy {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Config.Read
    .DESCRIPTION
        Returns the default OWA mailbox policy settings (third-party storage providers, direct
        file access). Read live from Exchange Online.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Tenant = $Request.Query.tenantFilter
    $Policy = New-ExoRequest -tenantid $Tenant -cmdlet 'Get-OwaMailboxPolicy' -cmdParams @{ Identity = 'OwaMailboxPolicy-Default' } -Select 'AdditionalStorageProvidersAvailable,DirectFileAccessOnPublicComputersEnabled,DirectFileAccessOnPrivateComputersEnabled'

    return ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = @($Policy)
        })
}
