function Get-CIPPSecret {
    <#
    .SYNOPSIS
        Reads a secret from Key Vault, or from the DevSecrets table in local development. Returns $null when it does not exist.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-zA-Z-]{1,127}$')]
        [string]$Name
    )

    if ([System.Environment]::GetEnvironmentVariable('AzureWebJobsStorage') -eq 'UseDevelopmentStorage=true' -or [System.Environment]::GetEnvironmentVariable('NonLocalHostAzurite') -eq 'true') {
        $Table = Get-CIPPTable -tablename 'DevSecrets'
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$Name' and RowKey eq '$Name'"
        if (-not $Row.Value) { return $null }
        return [string]$Row.Value
    }

    try {
        return Get-CippKeyVaultSecret -Name $Name -AsPlainText -ErrorAction Stop
    } catch {
        if ($_.Exception.Message -match '404|SecretNotFound') { return $null }
        throw
    }
}
