# Manual pagination hands Graph's @odata.nextLink back to the caller, who sends it in again. A government
# tenant's nextLink is on its own cloud's Graph host (graph.microsoft.us, dod-graph.microsoft.us), so the
# host check must accept that host for that tenant only, and keep accepting only graph.microsoft.com for a
# commercial tenant (redanthrax/CIPP#3).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))

    function Get-StringHash { param($String) 'PKHASH' }
    function New-GraphGetRequest { param($uri, $tenantid, $ComplexFilter, $noPagination, $Caller, [switch]$Stream, [switch]$SkipValueExtraction) }
    function Test-CIPPGraphEndpointBlocked { param($Uri, $Expand, [switch]$Throw) }
    function Get-CIPPTenantRequestCloud { param($TenantFilter) }
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphHelper/Get-CIPPCloudEndpoint.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/GraphRequests/Get-GraphRequestList.ps1')
}

Describe 'Get-GraphRequestList manual pagination nextLink host' {
    BeforeEach {
        Mock -CommandName New-GraphGetRequest -MockWith { [PSCustomObject]@{ id = 'u2' } }
    }

    It 'follows a <Cloud> tenant''s nextLink on <GraphHost>' -TestCases @(
        @{ Cloud = 'USGovHigh'; GraphHost = 'graph.microsoft.us' }
        @{ Cloud = 'USGovDoD'; GraphHost = 'dod-graph.microsoft.us' }
        @{ Cloud = 'Commercial'; GraphHost = 'graph.microsoft.com' }
    ) {
        param($Cloud, $GraphHost)
        Mock -CommandName Get-CIPPTenantRequestCloud -MockWith { $Cloud }
        $Next = "https://$GraphHost/beta/users?`$skiptoken=x"

        $Result = @(Get-GraphRequestList -TenantFilter 'contoso.example' -Endpoint 'users' -ManualPagination -nextLink $Next)

        $Result[0].id | Should -Be 'u2'
        Should -Invoke New-GraphGetRequest -Times 1 -ParameterFilter { $uri -eq $Next }
    }

    It 'refuses a nextLink on another cloud''s Graph host: <Cloud> tenant, <OtherHost>' -TestCases @(
        @{ Cloud = 'Commercial'; OtherHost = 'graph.microsoft.us' }
        @{ Cloud = 'Commercial'; OtherHost = 'dod-graph.microsoft.us' }
        @{ Cloud = 'USGovHigh'; OtherHost = 'graph.microsoft.com' }
        @{ Cloud = 'USGovHigh'; OtherHost = 'dod-graph.microsoft.us' }
        @{ Cloud = 'USGovDoD'; OtherHost = 'graph.microsoft.us' }
        @{ Cloud = 'USGovHigh'; OtherHost = 'example.com' }
    ) {
        param($Cloud, $OtherHost)
        Mock -CommandName Get-CIPPTenantRequestCloud -MockWith { $Cloud }

        { Get-GraphRequestList -TenantFilter 'contoso.example' -Endpoint 'users' -ManualPagination -nextLink "https://$OtherHost/beta/users?`$skiptoken=x" } |
            Should -Throw '*Invalid nextLink URL*'
        Should -Invoke New-GraphGetRequest -Times 0
    }

    It 'refuses the nextLink when the tenant''s cloud cannot be resolved' {
        Mock -CommandName Get-CIPPTenantRequestCloud -MockWith { throw 'Unknown cloud environment' }

        { Get-GraphRequestList -TenantFilter 'contoso.example' -Endpoint 'users' -ManualPagination -nextLink 'https://graph.microsoft.com/beta/users?$skiptoken=x' } |
            Should -Throw '*Invalid nextLink URL*'
        Should -Invoke New-GraphGetRequest -Times 0
    }
}
