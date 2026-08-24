function Set-CIPPServicePrincipalState {
    <#
    .SYNOPSIS
        Enables or disables a service principal tenant-wide.
    .DESCRIPTION
        Patches accountEnabled on the service principal. Disabling blocks every user's sign-in through
        the application and is the reversible way to neutralise a rogue application (re-enable it from
        the enterprise applications page if it turns out to be legitimate).
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER ServicePrincipalId
        The service principal object id.
    .PARAMETER AccountEnabled
        Desired state.
    .PARAMETER Headers
        CIPP request headers for logging.
    .PARAMETER APIName
        Logging API name.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)][string]$ServicePrincipalId,
        [Parameter(Mandatory = $true)][bool]$AccountEnabled,
        $Headers,
        [string]$APIName = 'BECRemediate'
    )

    $Verb = if ($AccountEnabled) { 'Enabled' } else { 'Disabled' }
    if (-not $PSCmdlet.ShouldProcess($ServicePrincipalId, "$Verb service principal")) { return }
    try {
        $Body = ConvertTo-Json -InputObject @{ accountEnabled = $AccountEnabled } -Compress
        $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$ServicePrincipalId" -tenantid $TenantFilter -type PATCH -body $Body -AsApp $true
        $Message = "$Verb service principal $ServicePrincipalId tenant-wide"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to set service principal $ServicePrincipalId to $($Verb.ToLower()): $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        throw $Message
    }
}
