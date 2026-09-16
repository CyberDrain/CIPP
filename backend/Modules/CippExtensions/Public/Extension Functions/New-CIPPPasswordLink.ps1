function New-CIPPPasswordLink {
    <#
    .SYNOPSIS
        Creates a password link using the enabled password sharing integration.
    .DESCRIPTION
        PWPush takes precedence when both providers are enabled. Returns false
        when disabled or unsuccessful, preserving the password flows' existing fallback.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Payload,
        [switch]$ThrowOnError
    )

    try {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $ConfigEntity = Get-CIPPAzDataTableEntity @Table
        if (-not $ConfigEntity.config) { return $false }
        $Configuration = $ConfigEntity.config | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $Message = 'Could not read the password sharing integration configuration.'
        Write-LogMessage -API PasswordLink -Message $Message -Sev 'Error'
        if ($ThrowOnError) { throw $Message }
        return $false
    }

    if ($Configuration.PWPush.Enabled -eq $true) {
        if ($PSCmdlet.ShouldProcess('PWPush', 'Create password link')) {
            return New-PwPushLink -Payload $Payload -ThrowOnError:$ThrowOnError
        }
    } elseif ($Configuration.OneTimeSecret.Enabled -eq $true) {
        if ($PSCmdlet.ShouldProcess('One-Time Secret', 'Create password link')) {
            return New-OneTimeSecretLink -Payload $Payload -Configuration $Configuration.OneTimeSecret -ThrowOnError:$ThrowOnError
        }
    }
    return $false
}
