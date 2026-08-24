function Disable-CIPPMailboxApp {
    <#
    .SYNOPSIS
        Disables an add-in for one mailbox.
    .DESCRIPTION
        Runs Disable-App for the add-in identity scoped to the mailbox. The add-in stays installed and
        can be re-enabled by the user or an administrator.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserPrincipalName
        The mailbox.
    .PARAMETER Identity
        The add-in identity (from Get-App).
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
        [Parameter(Mandatory = $true)][string]$UserPrincipalName,
        [Parameter(Mandatory = $true)][string]$Identity,
        $Headers,
        [string]$APIName = 'BECRemediate'
    )

    if (-not $PSCmdlet.ShouldProcess("$UserPrincipalName add-in $Identity", 'Disable-App')) { return }
    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Disable-App' -cmdParams @{ Identity = $Identity; Mailbox = $UserPrincipalName; Confirm = $false } -Anchor $UserPrincipalName
        $Message = "Disabled add-in $Identity for $UserPrincipalName"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to disable add-in $Identity for $UserPrincipalName`: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        throw $Message
    }
}
