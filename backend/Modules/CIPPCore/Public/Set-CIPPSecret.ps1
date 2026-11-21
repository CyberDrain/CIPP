function Set-CIPPSecret {
    <#
    .SYNOPSIS
        Stores a secret in Key Vault, or in the DevSecrets table in local development.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Set-CippKeyVaultSecret takes a SecureString.')]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-zA-Z-]{1,127}$')]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Set secret')) { return }

    if ([System.Environment]::GetEnvironmentVariable('AzureWebJobsStorage') -eq 'UseDevelopmentStorage=true' -or [System.Environment]::GetEnvironmentVariable('NonLocalHostAzurite') -eq 'true') {
        $Table = Get-CIPPTable -tablename 'DevSecrets'
        Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = $Name; RowKey = $Name; Value = $Value } -Force
        return
    }

    $null = Set-CippKeyVaultSecret -Name $Name -SecretValue (ConvertTo-SecureString -String $Value -AsPlainText -Force)
}
