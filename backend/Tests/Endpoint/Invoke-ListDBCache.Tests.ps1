BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Invoke-ListDBCache.ps1'

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    enum HttpStatusCode {
        OK = 200
        BadRequest = 400
    }

    function Get-Tenants { param($TenantFilter) }
    function Get-CIPPDbItem { param($TenantFilter, $Type, [switch]$CountsOnly) }
    function New-CIPPDbRequest { param($TenantFilter, $Type) }
    function Get-CIPPDbCoverage { param($TenantFilter, $Type, $Results) }

    . $FunctionPath
}

Describe 'Invoke-ListDBCache coverage' {
    BeforeEach {
        Mock New-CIPPDbRequest {
            @([PSCustomObject]@{ Tenant = 'one.example'; id = '1' })
        }
        Mock Get-CIPPDbCoverage {
            [PSCustomObject]@{ Type = $Type; Complete = $true }
        }
    }

    It 'adds coverage metadata when requested without changing Results' {
        $Request = [PSCustomObject]@{
            Query = [PSCustomObject]@{
                tenantFilter   = 'AllTenants'
                type           = 'Groups'
                includeCoverage = 'true'
            }
        }

        $Response = Invoke-ListDBCache -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results | Should -HaveCount 1
        $Response.Body.Coverage.Complete | Should -BeTrue
        Should -Invoke New-CIPPDbRequest -Times 1 -ParameterFilter {
            $TenantFilter -eq 'AllTenants' -and $Type -eq 'Groups'
        }
        Should -Invoke Get-CIPPDbCoverage -Times 1
    }

    It 'preserves the existing response shape by default' {
        $Request = [PSCustomObject]@{
            Query = [PSCustomObject]@{ tenantFilter = 'AllTenants'; type = 'Groups' }
        }

        $Response = Invoke-ListDBCache -Request $Request -TriggerMetadata $null

        $Response.Body.ContainsKey('Coverage') | Should -BeFalse
        Should -Invoke Get-CIPPDbCoverage -Times 0
    }
}
