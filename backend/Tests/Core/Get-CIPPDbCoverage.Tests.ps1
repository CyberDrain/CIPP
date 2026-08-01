BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPDbCoverage.ps1'

    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }

    . $FunctionPath
}

Describe 'Get-CIPPDbCoverage' {
    BeforeEach {
        Mock Get-Tenants {
            @(
                [PSCustomObject]@{ defaultDomainName = 'one.example' },
                [PSCustomObject]@{ defaultDomainName = 'two.example' },
                [PSCustomObject]@{ defaultDomainName = 'zero.example' }
            )
        }
        Mock Get-CIPPDbItem {
            @(
                [PSCustomObject]@{ PartitionKey = 'one.example'; DataCount = 2; Timestamp = [datetime]'2026-08-01' },
                [PSCustomObject]@{ PartitionKey = 'zero.example'; DataCount = 0; Timestamp = [datetime]'2026-08-01' }
            )
        }
    }

    It 'distinguishes complete, zero-row, missing, and count-mismatched tenants' {
        $Results = @(
            [PSCustomObject]@{ Tenant = 'one.example'; id = '1' }
        )

        $Coverage = Get-CIPPDbCoverage -TenantFilter AllTenants -Type Groups -Results $Results

        $Coverage.Complete | Should -BeFalse
        $Coverage.ExpectedTenantCount | Should -Be 3
        $Coverage.AvailableTenantCount | Should -Be 2
        $Coverage.DataCount | Should -Be 2
        $Coverage.ReturnedDataCount | Should -Be 1
        $Coverage.MissingTenants | Should -Be @('two.example')
        $Coverage.IncompleteTenants | Should -Be @('one.example', 'two.example')
        ($Coverage.Tenants | Where-Object Tenant -EQ 'zero.example').Complete | Should -BeTrue
        Should -Invoke Get-CIPPDbItem -Times 1 -ParameterFilter {
            $TenantFilter -eq 'allTenants' -and $Type -eq 'Groups' -and $CountsOnly
        }
    }
}
