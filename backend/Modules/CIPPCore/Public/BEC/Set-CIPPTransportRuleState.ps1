function Set-CIPPTransportRuleState {
    <#
    .SYNOPSIS
        Enables or disables a transport rule.
    .DESCRIPTION
        Runs Disable-TransportRule or Enable-TransportRule for the given rule identity. Transport rules
        are tenant-wide, so disabling one affects every mailbox; it is reversible.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER Identity
        The rule identity, name or GUID.
    .PARAMETER Enabled
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
        [Parameter(Mandatory = $true)][string]$Identity,
        [Parameter(Mandatory = $true)][bool]$Enabled,
        $Headers,
        [string]$APIName = 'BECRemediate'
    )

    $Cmdlet = if ($Enabled) { 'Enable-TransportRule' } else { 'Disable-TransportRule' }
    $Verb = if ($Enabled) { 'Enabled' } else { 'Disabled' }
    if (-not $PSCmdlet.ShouldProcess($Identity, $Cmdlet)) { return }
    try {
        $null = New-ExoRequest -tenantid $TenantFilter -cmdlet $Cmdlet -cmdParams @{ Identity = $Identity; Confirm = $false } -useSystemMailbox $true
        $Message = "$Verb transport rule '$Identity'"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to run $Cmdlet for '$Identity': $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        throw $Message
    }
}
