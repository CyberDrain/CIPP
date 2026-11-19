function Get-CIPPGovAppId {
    <#
    .SYNOPSIS
        Returns the Azure Government app's client id, or $null when it is not set up.
    .DESCRIPTION
        Reads only GovApplicationID, never the secret or certificate. Never throws.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $GuidPattern = '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\z'
    try {
        $ApplicationId = if ($env:CIPPGovAppLoaded -eq 'true') {
            [string]$env:GovApplicationID
        } elseif ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $Table = Get-CIPPTable -tablename 'DevSecrets'
            [string](Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'").GovApplicationID
        } else {
            [string](Get-CippKeyVaultSecret -VaultName (Get-CippKeyVaultName) -Name 'GovApplicationID' -AsPlainText -ErrorAction Stop)
        }
    } catch {
        if ($_.Exception.Message -notmatch '404|SecretNotFound') {
            Write-Information "Could not read the Azure Government app id: $($_.Exception.Message)"
        }
        return $null
    }
    if ($ApplicationId -match $GuidPattern) { return $ApplicationId }
    return $null
}
