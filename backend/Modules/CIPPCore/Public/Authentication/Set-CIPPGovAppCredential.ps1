function Set-CIPPGovAppCredential {
    <#
    .SYNOPSIS
        Stores the Azure Government app registration's application id and/or client secret.
    .DESCRIPTION
        Writes GovApplicationID / GovApplicationSecret to Key Vault (DevSecrets when running
        locally), the same store and protection as the SAM app's ApplicationID / ApplicationSecret.
        A parameter left out keeps its stored value. The certificate is stored by
        Set-CIPPSAMCertificate -Name GovSAMCertificate.

        Afterwards it drops this process's cached copy and bumps the credential version, so every
        worker reloads the government credentials and no cached government token outlives them.
    .FUNCTIONALITY
        Internal
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'The value is written straight to Key Vault (encrypted at rest)')]
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [string]$ApplicationId,
        [string]$ApplicationSecret
    )

    $Values = [ordered]@{}
    if ($PSBoundParameters.ContainsKey('ApplicationId')) {
        if ($ApplicationId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\z') { throw 'The application id must be a GUID.' }
        $Values['GovApplicationID'] = $ApplicationId
    }
    if ($PSBoundParameters.ContainsKey('ApplicationSecret')) {
        if ([string]::IsNullOrWhiteSpace($ApplicationSecret)) { throw 'The client secret cannot be empty.' }
        $Values['GovApplicationSecret'] = $ApplicationSecret
    }
    if ($Values.Count -eq 0) { return }
    if (-not $PSCmdlet.ShouldProcess('Azure Government app credentials', 'Store')) { return }

    if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
        $Table = Get-CIPPTable -tablename 'DevSecrets'
        $Secret = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
        if (!$Secret) { $Secret = [PSCustomObject]@{ PartitionKey = 'Secret'; RowKey = 'Secret' } }
        foreach ($Name in $Values.Keys) {
            $Secret | Add-Member -MemberType NoteProperty -Name $Name -Value $Values[$Name] -Force
        }
        $null = Add-CIPPAzDataTableEntity @Table -Entity $Secret -Force
    } else {
        $VaultName = Get-CippKeyVaultName
        foreach ($Name in $Values.Keys) {
            $null = Set-CippKeyVaultSecret -VaultName $VaultName -Name $Name -SecretValue (ConvertTo-SecureString -String $Values[$Name] -AsPlainText -Force)
        }
    }

    Remove-Item -Path env:CIPPGovAppLoaded -ErrorAction SilentlyContinue
    $null = Set-CIPPCredentialVersion
}
