# Pester tests for Remove-CIPPDirectTenantToken
# Verifies the stored per-tenant refresh token is removed from Key Vault (or DevSecrets locally),
# that the cached environment variable is cleared, and that cleanup failures never throw - callers
# invoke this while returning a different result to the user.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Remove-CIPPDirectTenantToken.ps1'

    # Minimal stubs so Mock has commands to replace during tests
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) }
    function Get-CippKeyVaultName { }
    function Remove-CippKeyVaultSecret { param($VaultName, $Name) }
    function Clear-CippTokenCache { param($TenantFilter) }

    . $FunctionPath
}

Describe 'Remove-CIPPDirectTenantToken' {
    BeforeEach {
        $script:TenantId = '11111111-1111-1111-1111-111111111111'
        $script:SecretName = '11111111_1111_1111_1111_111111111111'

        $script:OriginalStorage = $env:AzureWebJobsStorage
        $script:OriginalNonLocal = $env:NonLocalHostAzurite

        Mock -CommandName Get-CippKeyVaultName -MockWith { 'stub-vault' }
        Mock -CommandName Remove-CippKeyVaultSecret -MockWith { }
        Mock -CommandName Get-CIPPTable -MockWith { @{ Context = 'stub-table' } }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Clear-CippTokenCache -MockWith { 0 }
    }

    AfterEach {
        $env:AzureWebJobsStorage = $script:OriginalStorage
        $env:NonLocalHostAzurite = $script:OriginalNonLocal
        Remove-Item -Path "env:\$script:TenantId" -ErrorAction SilentlyContinue
        Remove-Item -Path "env:\$script:SecretName" -ErrorAction SilentlyContinue
    }

    Context 'Hosted (Key Vault) storage' {
        BeforeEach {
            $env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=https;AccountName=stub'
            $env:NonLocalHostAzurite = $null
        }

        It 'deletes the Key Vault secret named after the tenant' {
            Remove-CIPPDirectTenantToken -TenantId $script:TenantId
            Should -Invoke -CommandName Remove-CippKeyVaultSecret -Times 1 -Exactly -ParameterFilter {
                $Name -eq '11111111-1111-1111-1111-111111111111'
            }
        }

        It 'clears the cached environment variable' {
            Set-Item -Path "env:\$script:TenantId" -Value 'stub-refresh-token' -Force
            Remove-CIPPDirectTenantToken -TenantId $script:TenantId
            Test-Path -Path "env:\$script:TenantId" | Should -BeFalse
        }

        It 'does not throw when the secret cannot be deleted' {
            Mock -CommandName Remove-CippKeyVaultSecret -MockWith { throw 'SecretNotFound' }
            { Remove-CIPPDirectTenantToken -TenantId $script:TenantId } | Should -Not -Throw
        }

        It 'does not touch DevSecrets' {
            Remove-CIPPDirectTenantToken -TenantId $script:TenantId
            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }
    }

    Context 'Local development storage' {
        BeforeEach {
            $env:AzureWebJobsStorage = 'UseDevelopmentStorage=true'
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                [pscustomobject]@{
                    PartitionKey                          = 'Secret'
                    RowKey                                = 'Secret'
                    '11111111_1111_1111_1111_111111111111' = 'stub-refresh-token'
                }
            }
        }

        It 'clears the stored secret value in the DevSecrets table' {
            Remove-CIPPDirectTenantToken -TenantId $script:TenantId
            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter {
                $Entity.'11111111_1111_1111_1111_111111111111' -eq ''
            }
        }

        It 'does not call Key Vault' {
            Remove-CIPPDirectTenantToken -TenantId $script:TenantId
            Should -Invoke -CommandName Remove-CippKeyVaultSecret -Times 0 -Exactly
        }

        It 'leaves the table alone when no secret is stored for the tenant' {
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                [pscustomobject]@{ PartitionKey = 'Secret'; RowKey = 'Secret' }
            }
            Remove-CIPPDirectTenantToken -TenantId $script:TenantId
            Should -Invoke -CommandName Add-CIPPAzDataTableEntity -Times 0 -Exactly
        }
    }

    It 'drops the tenant''s cached tokens (redanthrax/CIPP#2)' {
        $env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=https'
        $env:NonLocalHostAzurite = $null
        Remove-CIPPDirectTenantToken -TenantId $script:TenantId
        Should -Invoke Clear-CippTokenCache -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq $script:TenantId }
    }

    # Invoke-ExecAddTenant passes the request body's tenantId straight through on every rejection
    # (redanthrax/CIPP#2 made those reachable with any unparseable token). The secret is named after
    # that value, so it must never be allowed to name CIPP's own credentials.
    Context 'tenant id that is not a direct tenant GUID' {
        BeforeEach {
            $script:OriginalPartner = $env:TenantID
            $env:TenantID = '99999999-9999-9999-9999-999999999999'
            Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
                [pscustomobject]@{ PartitionKey = 'Secret'; RowKey = 'Secret'; RefreshToken = 'partner-rt'; ApplicationSecret = 'sam-secret' }
            }
        }
        AfterEach { $env:TenantID = $script:OriginalPartner }

        It 'never deletes or clears <Value> (<Storage>)' -ForEach @(
            @{ Value = 'RefreshToken'; Storage = 'DefaultEndpointsProtocol=https' }
            @{ Value = 'ApplicationSecret'; Storage = 'DefaultEndpointsProtocol=https' }
            @{ Value = 'RefreshToken'; Storage = 'UseDevelopmentStorage=true' }
            @{ Value = 'ApplicationSecret'; Storage = 'UseDevelopmentStorage=true' }
            @{ Value = '99999999-9999-9999-9999-999999999999'; Storage = 'DefaultEndpointsProtocol=https' }
            @{ Value = '99999999-9999-9999-9999-999999999999'; Storage = 'UseDevelopmentStorage=true' }
            @{ Value = '11111111-1111-1111-1111-111111111111/x'; Storage = 'DefaultEndpointsProtocol=https' }
        ) {
            $env:AzureWebJobsStorage = $Storage
            $env:NonLocalHostAzurite = $null
            { Remove-CIPPDirectTenantToken -TenantId $Value -WarningAction SilentlyContinue } | Should -Not -Throw
            Should -Invoke Remove-CippKeyVaultSecret -Times 0 -Exactly
            Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
            Should -Invoke Clear-CippTokenCache -Times 0 -Exactly
        }
    }
}
