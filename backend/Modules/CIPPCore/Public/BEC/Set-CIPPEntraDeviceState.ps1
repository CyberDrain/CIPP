function Set-CIPPEntraDeviceState {
    <#
    .SYNOPSIS
        Disables, enables or deletes an Entra device object.
    .DESCRIPTION
        Patches accountEnabled on the device (reversible) or deletes the device object with -Remove
        (not reversible; the device has to register again). Disabling a device stops it satisfying
        device-based Conditional Access and primary refresh token issuance.
    .PARAMETER TenantFilter
        Tenant default domain name.
    .PARAMETER DeviceId
        The device object id.
    .PARAMETER AccountEnabled
        Desired state when not removing.
    .PARAMETER Remove
        Delete the device object instead.
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
        [Parameter(Mandatory = $true)][string]$DeviceId,
        [bool]$AccountEnabled = $false,
        [switch]$Remove,
        $Headers,
        [string]$APIName = 'BECRemediate'
    )

    $Operation = if ($Remove) { 'Deleted' } elseif ($AccountEnabled) { 'Enabled' } else { 'Disabled' }
    if (-not $PSCmdlet.ShouldProcess($DeviceId, "$Operation device")) { return }
    try {
        if ($Remove) {
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/devices/$DeviceId" -tenantid $TenantFilter -type DELETE -AsApp $true
        } else {
            $Body = ConvertTo-Json -InputObject @{ accountEnabled = $AccountEnabled } -Compress
            $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/devices/$DeviceId" -tenantid $TenantFilter -type PATCH -body $Body -AsApp $true
        }
        $Message = "$Operation Entra device $DeviceId"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Info'
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed: $($Operation.ToLower()) Entra device $DeviceId`: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message $Message -Sev 'Error' -LogData $ErrorMessage
        throw $Message
    }
}
