function Remove-CIPPSecret {
    <#
    .SYNOPSIS
        Deletes a secret from Key Vault, or from the DevSecrets table in local development. A missing secret is not an error.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-zA-Z-]{1,127}$')]
        [string]$Name
    )

    if (-not $PSCmdlet.ShouldProcess($Name, 'Remove secret')) { return }

    if ([System.Environment]::GetEnvironmentVariable('AzureWebJobsStorage') -eq 'UseDevelopmentStorage=true' -or [System.Environment]::GetEnvironmentVariable('NonLocalHostAzurite') -eq 'true') {
        $Table = Get-CIPPTable -tablename 'DevSecrets'
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$Name' and RowKey eq '$Name'" -Property PartitionKey, RowKey
        if ($Row) { Remove-CIPPAzDataTableEntity @Table -Entity $Row -Force -ErrorAction Stop }
        return
    }

    $null = Remove-CippKeyVaultSecret -Name $Name
}
