function Set-CIPPCASMailboxProtocols {
    <#
    .SYNOPSIS
        Turns client access protocols on or off for a mailbox.
    .DESCRIPTION
        Maps protocol names to Set-CASMailbox switches and applies them in one call. SmtpAuth maps to
        SmtpClientAuthenticationDisabled, which is inverted: disabling the protocol sets it to $true.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER UserPrincipalName
        The mailbox.
    .PARAMETER Protocols
        Any of EWS, IMAP, POP, ActiveSync, OWA, MAPI, ECP, SmtpAuth.
    .PARAMETER Enabled
        Desired state for the listed protocols.
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
        [Parameter(Mandatory = $true)][ValidateSet('EWS', 'IMAP', 'POP', 'ActiveSync', 'OWA', 'MAPI', 'ECP', 'SmtpAuth')][string[]]$Protocols,
        [Parameter(Mandatory = $true)][bool]$Enabled,
        $Headers,
        [string]$APIName = 'BECRemediate'
    )

    $Map = @{ EWS = 'EWSEnabled'; IMAP = 'IMAPEnabled'; POP = 'POPEnabled'; ActiveSync = 'ActiveSyncEnabled'; OWA = 'OWAEnabled'; MAPI = 'MAPIEnabled'; ECP = 'ECPEnabled' }
    $CmdParams = @{ Identity = $UserPrincipalName }
    foreach ($Protocol in ($Protocols | Select-Object -Unique)) {
        if ($Protocol -eq 'SmtpAuth') {
            $CmdParams['SmtpClientAuthenticationDisabled'] = (-not $Enabled)
        } else {
            $CmdParams[$Map[$Protocol]] = $Enabled
        }
    }
    $Verb = if ($Enabled) { 'Enabled' } else { 'Disabled' }
    if (-not $PSCmdlet.ShouldProcess($UserPrincipalName, "$Verb $($Protocols -join ', ')")) { return }
    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet 'Set-CASMailbox' -cmdParams $CmdParams -Anchor $UserPrincipalName
        $Message = "$Verb $($Protocols -join ', ') for $UserPrincipalName"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to set protocols ($($Protocols -join ', ')) for $UserPrincipalName`: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        throw $Message
    }
}
