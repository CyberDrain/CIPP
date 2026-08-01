BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPDbRequest.ps1'

    if (-not ('CIPP.CippJson' -as [type])) {
        Add-Type -TypeDefinition @'
namespace CIPP {
    public class ParsedItem { }
    public static class CippJson {
        public static object ConvertFromJson(string json, string[] projection) {
            return new ParsedItem();
        }
    }
}
'@
    }

    function Get-CippTable { param($tablename) @{ Table = $tablename } }
    function Get-Tenants { param($TenantFilter, [switch]$IncludeErrors) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Get-CIPPAzDataTableEntity { param($Table, $Filter) }
    function Write-LogMessage { param($API, $tenant, $message, $sev) }

    . $FunctionPath
}

Describe 'New-CIPPDbRequest AllTenants' {
    BeforeEach {
        $script:CIPPDbRequestTenantCache = @{}
        Mock Get-Tenants {
            @(
                [PSCustomObject]@{ defaultDomainName = 'one.example' },
                [PSCustomObject]@{ defaultDomainName = 'two.example' }
            )
        }
        Mock Get-CIPPAzDataTableEntity {
            @(
                [PSCustomObject]@{ PartitionKey = 'one.example'; RowKey = 'Groups-1'; Data = '{"id":"1"}' },
                [PSCustomObject]@{ PartitionKey = 'two.example'; RowKey = 'Groups-2'; Data = '{"id":"2"}' },
                [PSCustomObject]@{ PartitionKey = 'excluded.example'; RowKey = 'Groups-3'; Data = '{"id":"3"}' }
            )
        }
    }

    It 'queries across partitions and labels records with their managed tenant' {
        $Results = @(New-CIPPDbRequest -TenantFilter AllTenants -Type Groups)

        $Results | Should -HaveCount 2
        $Results.Tenant | Should -Be @('one.example', 'two.example')
        Should -Invoke Get-Tenants -Times 1 -ParameterFilter { $IncludeErrors }
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -ParameterFilter {
            $Filter -eq "RowKey ge 'Groups-' and RowKey lt 'Groups.'"
        }
    }
}
