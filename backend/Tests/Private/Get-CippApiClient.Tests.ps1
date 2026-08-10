# Pester tests for Get-CippApiClient
# Verifies IPRange normalisation. A stored empty range ("[]") must resolve to @('Any') so the
# client is not created dead; a populated range is preserved verbatim; and both the absent-property
# and malformed-JSON cases fall back to @('Any'). The empty case must also not leak a bare 'Any'
# string into the function's output stream alongside the returned client objects.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Authentication/Get-CippApiClient.ps1'

    # Minimal stubs so Mock has commands to replace during tests
    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) }

    . $FunctionPath
}

Describe 'Get-CippApiClient' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { @{} }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith { $script:StoredClient }
    }

    Context 'IPRange normalisation' {
        It 'resolves a stored empty range "[]" to Any so the client is not created dead' {
            $script:StoredClient = [PSCustomObject]@{ RowKey = 'client-1'; AppName = 'demo'; Role = $null; IPRange = '[]'; Enabled = $true; MCPAllowed = $false }

            $Client = Get-CippApiClient | Where-Object { $_.ClientId -eq 'client-1' }

            @($Client.IPRange).Count | Should -Be 1
            @($Client.IPRange)[0] | Should -Be 'Any'
        }

        It 'preserves a populated range verbatim' {
            $script:StoredClient = [PSCustomObject]@{ RowKey = 'client-1'; AppName = 'demo'; Role = $null; IPRange = '["10.0.0.0/8"]'; Enabled = $true; MCPAllowed = $false }

            $Client = Get-CippApiClient | Where-Object { $_.ClientId -eq 'client-1' }

            @($Client.IPRange).Count | Should -Be 1
            @($Client.IPRange)[0] | Should -Be '10.0.0.0/8'
        }

        It 'falls back to Any when the IPRange property is absent (legacy client)' {
            $script:StoredClient = [PSCustomObject]@{ RowKey = 'client-1'; AppName = 'demo'; Role = $null; Enabled = $true; MCPAllowed = $false }

            $Client = Get-CippApiClient | Where-Object { $_.ClientId -eq 'client-1' }

            @($Client.IPRange)[0] | Should -Be 'Any'
        }

        It 'falls back to Any when the stored IPRange is malformed JSON' {
            $script:StoredClient = [PSCustomObject]@{ RowKey = 'client-1'; AppName = 'demo'; Role = $null; IPRange = '{ not valid json'; Enabled = $true; MCPAllowed = $false }

            $Client = Get-CippApiClient | Where-Object { $_.ClientId -eq 'client-1' }

            @($Client.IPRange)[0] | Should -Be 'Any'
        }
    }

    Context 'Output stream integrity' {
        It 'returns only client objects - no bare Any string leaks into the collection' {
            $script:StoredClient = [PSCustomObject]@{ RowKey = 'client-1'; AppName = 'demo'; Role = $null; IPRange = '[]'; Enabled = $true; MCPAllowed = $false }

            $Result = @(Get-CippApiClient)

            $Result.Count | Should -Be 1
            ($Result | Where-Object { $_ -is [string] }) | Should -BeNullOrEmpty
        }
    }
}
