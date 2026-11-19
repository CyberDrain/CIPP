function Get-CIPPGovAppCredential {
    <#
    .SYNOPSIS
        Loads the Azure Government app registration credentials.
    .DESCRIPTION
        Lazily loaded from Key Vault (DevSecrets locally) into env vars. Missing values set Configured to $false;
        other storage errors throw so a transient failure is not cached as "not configured".
        The result holds secret material - never log or return it.
    .PARAMETER Force
        Re-read storage even when a cached copy exists.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    $Names = @('GovApplicationID', 'GovApplicationSecret', 'GovSAMCertificate')

    if ($Force -or $env:CIPPGovAppLoaded -ne 'true') {
        $Values = @{}
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $Table = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
            foreach ($Name in $Names) { $Values[$Name] = [string]$Secret.$Name }
        } else {
            $VaultName = Get-CippKeyVaultName
            foreach ($Name in $Names) {
                try {
                    $Values[$Name] = [string](Get-CippKeyVaultSecret -VaultName $VaultName -Name $Name -AsPlainText -ErrorAction Stop)
                } catch {
                    if ($_.Exception.Message -match '404|SecretNotFound') { $Values[$Name] = '' } else { throw }
                }
            }
        }
        foreach ($Name in $Names) {
            if ($Values[$Name]) { Set-Item -Path "env:$Name" -Value $Values[$Name] -Force } else { Remove-Item -Path "env:$Name" -ErrorAction SilentlyContinue }
        }
        $env:CIPPGovAppLoaded = 'true'
    }

    $ApplicationId = [string]$env:GovApplicationID
    $ValidId = $ApplicationId -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\z'
    $HasSecret = -not [string]::IsNullOrEmpty($env:GovApplicationSecret)
    $HasCertificate = -not [string]::IsNullOrEmpty($env:GovSAMCertificate)
    return [pscustomobject]@{
        ApplicationId     = if ($ValidId) { $ApplicationId } else { $null }
        ApplicationSecret = if ($HasSecret) { [string]$env:GovApplicationSecret } else { $null }
        PfxBase64         = if ($HasCertificate) { [string]$env:GovSAMCertificate } else { $null }
        HasSecret         = $HasSecret
        HasCertificate    = $HasCertificate
        Configured        = $ValidId -and ($HasSecret -or $HasCertificate)
    }
}
