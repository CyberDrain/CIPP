function Remove-CIPPDirectTenantToken {
    <#
    .FUNCTIONALITY
    Internal
    .SYNOPSIS
    Removes the per-tenant refresh token stored for a direct tenant.
    .DESCRIPTION
    Direct tenants authenticate with their own refresh token, kept in Key Vault (or the DevSecrets
    table when running locally) under the tenant id, and cached in an environment variable of the
    same name. This removes both so a tenant that is not a direct tenant cannot fall back to it.
    Cleanup is best effort - failures are logged rather than thrown, because callers use this while
    handling another outcome.
    .PARAMETER TenantId
    The customer id (GUID) of the tenant whose stored credential should be removed.
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId
    )

    # The secret is named after the tenant id, so a caller-supplied value such as 'RefreshToken' or
    # 'ApplicationSecret' would name one of CIPP's own credentials. Direct tenant tokens are only
    # stored under a tenant GUID (Invoke-ExecUpdateRefreshToken), and never for the partner tenant.
    if ($TenantId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}\z' -or $TenantId -eq $env:TenantID) {
        Write-Warning 'Not removing a direct tenant refresh token: the tenant id is not a direct tenant GUID.'
        return
    }

    if (-not $PSCmdlet.ShouldProcess($TenantId, 'Remove direct tenant refresh token')) {
        return
    }

    try {
        if ($env:AzureWebJobsStorage -eq 'UseDevelopmentStorage=true' -or $env:NonLocalHostAzurite -eq 'true') {
            $SecretName = $TenantId -replace '-', '_'
            $DevSecretsTable = Get-CIPPTable -tablename 'DevSecrets'
            $Secret = Get-CIPPAzDataTableEntity @DevSecretsTable -Filter "PartitionKey eq 'Secret' and RowKey eq 'Secret'"
            if ($Secret -and $Secret.PSObject.Properties.Name -contains $SecretName) {
                $Secret.$SecretName = ''
                $null = Add-CIPPAzDataTableEntity @DevSecretsTable -Entity $Secret -Force
            }
            Remove-Item -Path "env:\$SecretName" -ErrorAction SilentlyContinue
        } else {
            $KeyVaultName = Get-CippKeyVaultName
            $null = Remove-CippKeyVaultSecret -VaultName $KeyVaultName -Name $TenantId -ErrorAction Stop
        }

        Remove-Item -Path "env:\$TenantId" -ErrorAction SilentlyContinue
        # Access tokens minted from the removed refresh token (in either cloud - redanthrax/CIPP#2) and the
        # tenant's cloud marker go with it. Storage is the same for every cloud: there is no
        # authority-side revocation, the refresh token simply stops being used.
        $null = Clear-CippTokenCache -TenantFilter $TenantId
        Write-Information "Removed stored direct tenant refresh token for $TenantId"
    } catch {
        Write-Warning "Failed to remove the stored direct tenant refresh token for $TenantId - $($_.Exception.Message)"
    }
}
