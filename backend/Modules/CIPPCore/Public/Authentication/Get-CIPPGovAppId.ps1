function Get-CIPPGovAppId {
    <#
    .SYNOPSIS
        Returns the Azure Government app's client id, or $null when it is not set up (redanthrax/CIPP#2).
    .DESCRIPTION
        For callers that only need the public client id, such as ExecListAppId for the sign-in button.
        Reads the GovApplicationID value alone, so the gov secret and certificate are never loaded into
        memory for it, and a commercial instance without a gov app costs one "not found" lookup.
        Uses the copy Get-CIPPGovAppCredential cached in the process when there is one.

        Never throws: any storage error returns $null, because the caller treats "unknown" the same as
        "not configured" (government sign-in stays disabled).
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
