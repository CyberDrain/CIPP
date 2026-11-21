BeforeAll {
    $BackendRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Public = Join-Path $BackendRoot 'Modules/CIPPCore/Public'
    function Get-CIPPTable { param($tablename) @{ TableName = $tablename } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-CippKeyVaultSecret { param($Name, [switch]$AsPlainText) }
    function Set-CippKeyVaultSecret { param($Name, $SecretValue) }
    function Remove-CippKeyVaultSecret { param($Name) }
    . (Join-Path $Public 'Get-CIPPSecret.ps1')
    . (Join-Path $Public 'Set-CIPPSecret.ps1')
    . (Join-Path $Public 'Remove-CIPPSecret.ps1')
    $script:OriginalStorage = $env:AzureWebJobsStorage
    $script:OriginalAzurite = $env:NonLocalHostAzurite
}

AfterAll {
    $env:AzureWebJobsStorage = $script:OriginalStorage
    $env:NonLocalHostAzurite = $script:OriginalAzurite
}

Describe 'CIPP secret helpers in local development' {
    BeforeEach {
        $env:AzureWebJobsStorage = 'UseDevelopmentStorage=true'
        $env:NonLocalHostAzurite = $null
        Mock Get-CippKeyVaultSecret { throw 'Key Vault must not be used' }
        Mock Set-CippKeyVaultSecret { throw 'Key Vault must not be used' }
        Mock Remove-CippKeyVaultSecret { throw 'Key Vault must not be used' }
    }

    It 'reads the Value column of the DevSecrets row keyed by name' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'CloudBackupDest-x'; RowKey = 'CloudBackupDest-x'; Value = 's3cret' } }
        Get-CIPPSecret -Name 'CloudBackupDest-x' | Should -Be 's3cret'
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'DevSecrets' -and $Filter -eq "PartitionKey eq 'CloudBackupDest-x' and RowKey eq 'CloudBackupDest-x'" }
    }

    It 'returns $null when the row is missing' {
        Mock Get-CIPPAzDataTableEntity { }
        Get-CIPPSecret -Name 'CloudBackupDest-x' | Should -BeNullOrEmpty
    }

    It 'writes the DevSecrets row' {
        Mock Add-CIPPAzDataTableEntity { }
        Set-CIPPSecret -Name 'CloudBackupDest-x' -Value 's3cret'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $TableName -eq 'DevSecrets' -and $Entity.PartitionKey -eq 'CloudBackupDest-x' -and $Entity.RowKey -eq 'CloudBackupDest-x' -and $Entity.Value -eq 's3cret' -and $Force
        }
    }

    It 'removes the DevSecrets row when it exists and ignores a missing one' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'CloudBackupDest-x'; RowKey = 'CloudBackupDest-x' } }
        Mock Remove-CIPPAzDataTableEntity { }
        Remove-CIPPSecret -Name 'CloudBackupDest-x'
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -ParameterFilter { $Entity.RowKey -eq 'CloudBackupDest-x' }

        Mock Get-CIPPAzDataTableEntity { }
        Remove-CIPPSecret -Name 'CloudBackupDest-y'
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'treats NonLocalHostAzurite as development' {
        $env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=http;AccountName=devstoreaccount1'
        $env:NonLocalHostAzurite = 'true'
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ Value = 'dev' } }
        Get-CIPPSecret -Name 'CloudBackupDest-x' | Should -Be 'dev'
    }
}

Describe 'CIPP secret helpers with Key Vault' {
    BeforeEach {
        $env:AzureWebJobsStorage = 'DefaultEndpointsProtocol=https;AccountName=prod'
        $env:NonLocalHostAzurite = $null
        Mock Get-CIPPAzDataTableEntity { throw 'DevSecrets must not be used' }
        Mock Add-CIPPAzDataTableEntity { throw 'DevSecrets must not be used' }
    }

    It 'reads the secret as plain text' {
        Mock Get-CippKeyVaultSecret { 'kv-secret' }
        Get-CIPPSecret -Name 'CloudBackupDest-x' | Should -Be 'kv-secret'
        Should -Invoke Get-CippKeyVaultSecret -ParameterFilter { $Name -eq 'CloudBackupDest-x' -and $AsPlainText }
    }

    It 'returns $null for a secret Key Vault does not have' {
        Mock Get-CippKeyVaultSecret { throw "Key Vault secret retrieval failed: Failed to retrieve secret 'x': Response status code does not indicate success: 404 (Not Found)." }
        Get-CIPPSecret -Name 'CloudBackupDest-x' | Should -BeNullOrEmpty
    }

    It 'rethrows other Key Vault failures' {
        Mock Get-CippKeyVaultSecret { throw 'Key Vault secret retrieval failed: 403 Forbidden' }
        { Get-CIPPSecret -Name 'CloudBackupDest-x' } | Should -Throw '*403*'
    }

    It 'writes the secret as a SecureString' {
        Mock Set-CippKeyVaultSecret { }
        Set-CIPPSecret -Name 'CloudBackupDest-x' -Value 'kv-secret'
        Should -Invoke Set-CippKeyVaultSecret -Times 1 -ParameterFilter {
            $Name -eq 'CloudBackupDest-x' -and [System.Net.NetworkCredential]::new('', $SecretValue).Password -eq 'kv-secret'
        }
    }

    It 'removes the secret' {
        Mock Remove-CippKeyVaultSecret { }
        Remove-CIPPSecret -Name 'CloudBackupDest-x'
        Should -Invoke Remove-CippKeyVaultSecret -Times 1 -ParameterFilter { $Name -eq 'CloudBackupDest-x' }
    }

    It 'rejects names Key Vault cannot hold' {
        { Get-CIPPSecret -Name "x' or PartitionKey ne 'y" } | Should -Throw
    }
}
