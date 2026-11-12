function Get-CIPPGovAppCredential {
    <#
    .SYNOPSIS
        Loads the Azure Government app registration credentials (redanthrax/CIPP#2).
    .DESCRIPTION
        A commercial multi-tenant app cannot be consented in a GCC High or DoD tenant, so CIPP signs
        in to direct government tenants with a separate app registered in Azure Government. Its
        credentials sit next to the SAM app's and get the same protection:

            Key Vault secret     DevSecrets column (local)   content
            GovApplicationID     GovApplicationID            application (client) id
            GovApplicationSecret GovApplicationSecret        client secret (optional)
            GovSAMCertificate    GovSAMCertificate           passwordless PFX, base64 (optional)

        Loaded lazily - only when a government tenant needs a token - into process environment
        variables, the same cache the SAM credentials use, so commercial instances never read
        them. Get-CIPPAuthentication drops the cached copy whenever credentials are reloaded (for
        example after Set-CIPPCredentialVersion), and the next call reads storage again.

        Never throws for missing values: Configured is $false instead, and the caller decides how to
        fail. A storage error other than "not found" is thrown, so a transient Key Vault failure is
        not cached as "not configured".
    .PARAMETER Force
        Re-read storage even when a cached copy exists.
    .OUTPUTS
        PSCustomObject: ApplicationId, ApplicationSecret, PfxBase64, HasSecret, HasCertificate, Configured.
        Contains secret material - never log or return it from an endpoint.
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
