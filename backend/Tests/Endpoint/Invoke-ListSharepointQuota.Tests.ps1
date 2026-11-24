# Pester tests for Invoke-ListSharepointQuota
# Covers the cached single-tenant read, including an empty cache.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListSharepointQuota.ps1' -File -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
    if (-not $FunctionPath) { throw 'Could not locate Invoke-ListSharepointQuota.ps1 under Modules/' }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPDbItem { param($tenantFilter, $Type, [switch]$ByTenant) }

    . $FunctionPath
}

Describe 'Invoke-ListSharepointQuota' {
    BeforeEach {
        $script:Request = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListSharepointQuota' }; Headers = @{}; Query = @{ tenantFilter = 'contoso.onmicrosoft.com' } }
    }

    It 'returns NotFound with a sync hint when only the count row is cached' {
        Mock -CommandName Get-CIPPDbItem -MockWith { [pscustomobject]@{ RowKey = 'SharePointUsageReport-Count'; Data = '{"Count":0}' } }

        $Response = Invoke-ListSharepointQuota -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::NotFound)
        $Response.Body.Results | Should -Be 'No SharePoint usage data cached for contoso.onmicrosoft.com. Sync the report data first.'
    }

    It 'returns the cached quota' {
        Mock -CommandName Get-CIPPDbItem -MockWith {
            [pscustomobject]@{ RowKey = 'SharePointUsageReport-Count'; Data = '{"Count":1}' }
            [pscustomobject]@{ RowKey = 'SharePointUsageReport-1'; Data = '{"GeoUsedStorageMB":512,"TenantStorageMB":1024,"Percentage":50,"Dashboard":"50 / 100","GeoLocations":[]}' }
        }

        $Response = Invoke-ListSharepointQuota -Request $Request -TriggerMetadata $null

        $Response.StatusCode | Should -Be ([int][System.Net.HttpStatusCode]::OK)
        $Response.Body.GeoUsedStorageMB | Should -Be 512
        $Response.Body.TenantStorageMB | Should -Be 1024
    }
}
