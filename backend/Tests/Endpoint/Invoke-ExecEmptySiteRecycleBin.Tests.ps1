# Pester tests for Invoke-ExecEmptySiteRecycleBin and Invoke-ListSiteRecycleBinSummary

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $ExecPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ExecEmptySiteRecycleBin.ps1'
    $SummaryPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ListSiteRecycleBinSummary.ps1'
    if (-not (Test-Path $ExecPath)) { throw "Could not locate $ExecPath" }
    if (-not (Test-Path $SummaryPath)) { throw "Could not locate $SummaryPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-SharePointAdminLink { param($Public, $tenantFilter) [PSCustomObject]@{ SharePointUrl = 'https://contoso.sharepoint.com'; AdminUrl = 'https://contoso-admin.sharepoint.com' } }
    function Resolve-CIPPSharePointRestContext {
        param($TenantFilter, $SiteUrl)
        $BaseUri = 'https://contoso.sharepoint.com/sites/a/_api'
        [PSCustomObject]@{
            Scope   = 'https://contoso.sharepoint.com/.default'
            Headers = @{ Accept = 'application/json;odata=nometadata' }
            BaseUri = $BaseUri
            WebUri  = "$BaseUri/web"
        }
    }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Message } }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippBulkStatusCode.ps1')

    . $ExecPath
    . $SummaryPath
}

Describe 'Invoke-ExecEmptySiteRecycleBin' {
    BeforeEach {
        $script:GraphPostCalls = 0
        $script:GraphGetCalls = 0
        $script:RecycleBinItems = @(
            [PSCustomObject]@{ Id = '1'; Size = 100; ItemState = 1 }
            [PSCustomObject]@{ Id = '2'; Size = 200; ItemState = 1 }
        )
        function global:New-GraphPostRequest {
            param(
                $uri, $tenantid, $scope, $type, $body, $contentType, $AddedHeaders,
                [switch]$UseCertificate,
                $AsApp
            )
            $script:GraphPostCalls++
            if ($uri -like '*deleteAll*') {
                $script:RecycleBinItems = @()
            }
        }
        function global:New-GraphGetRequest {
            param(
                $uri, $tenantid, $scope, $AsApp, $extraHeaders,
                [switch]$UseCertificate,
                [bool]$noPagination,
                [switch]$SkipValueExtraction
            )
            $script:GraphGetCalls++
            [PSCustomObject]@{
                value = @($script:RecycleBinItems)
            }
        }
    }

    It 'returns BadRequest when SiteUrl is missing' {
        $Response = Invoke-ExecEmptySiteRecycleBin -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecEmptySiteRecycleBin' }
                Headers = @{}
                Body    = [pscustomobject]@{ tenantFilter = 'contoso.onmicrosoft.com'; Stage = 'Both' }
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }

    It 'returns BadRequest for invalid Stage' {
        $Response = Invoke-ExecEmptySiteRecycleBin -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecEmptySiteRecycleBin' }
                Headers = @{}
                Body    = [pscustomobject]@{
                    tenantFilter = 'contoso.onmicrosoft.com'
                    SiteUrl      = 'https://contoso.sharepoint.com/sites/a'
                    Stage        = 'Nope'
                }
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
        $Response.Body.Results | Should -Match 'Invalid Stage'
    }

    It 'verifies deletion and returns accurate counts' {
        $Response = Invoke-ExecEmptySiteRecycleBin -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecEmptySiteRecycleBin' }
                Headers = @{}
                Body    = [pscustomobject]@{
                    tenantFilter = 'contoso.onmicrosoft.com'
                    SiteUrl      = 'https://contoso.sharepoint.com/sites/a'
                    Stage        = 'First'
                }
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $script:GraphGetCalls | Should -BeGreaterThan 0
        $Response.Body.itemsBefore | Should -Be 2
        $Response.Body.itemsDeleted | Should -Be 2
        $Response.Body.itemsRemaining | Should -Be 0
        $Response.Body.bytesFreed | Should -Be 300
        $Response.Body.Results | Should -Match 'Successfully emptied'
    }

    It 'reports partial success when items remain' {
        $script:RecycleBinItems = @(
            [PSCustomObject]@{ Id = '1'; Size = 100; ItemState = 1 }
        )
        function global:New-GraphPostRequest {
            param($uri, $tenantid, $scope, $type, $body, $contentType, $AddedHeaders, [switch]$UseCertificate, $AsApp)
            $script:GraphPostCalls++
        }
        
        $Response = Invoke-ExecEmptySiteRecycleBin -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ExecEmptySiteRecycleBin' }
                Headers = @{}
                Body    = [pscustomobject]@{
                    tenantFilter = 'contoso.onmicrosoft.com'
                    SiteUrl      = 'https://contoso.sharepoint.com/sites/a'
                    Stage        = 'First'
                }
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.itemsRemaining | Should -BeGreaterThan 0
        $Response.Body.Results | Should -Match 'may be held by retention policy'
    }
}

Describe 'Invoke-ListSiteRecycleBinSummary' {
    BeforeEach {
        $script:GetRequestCount = 0
        function global:New-GraphGetRequest {
            param(
                $uri, $tenantid, $scope, $AsApp, $extraHeaders,
                [switch]$UseCertificate,
                [bool]$noPagination,
                [switch]$SkipValueExtraction
            )
            $script:GetRequestCount++
            if ($uri -match '\$skip=0') {
                [PSCustomObject]@{
                    value = @(
                        [PSCustomObject]@{ Id = '1'; Size = 100; ItemState = 1 }
                        [PSCustomObject]@{ Id = '2'; Size = 50; ItemState = 2 }
                    )
                }
            } else {
                [PSCustomObject]@{
                    value = @()
                }
            }
        }
    }

    It 'returns BadRequest when SiteUrl is missing' {
        $Response = Invoke-ListSiteRecycleBinSummary -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ListSiteRecycleBinSummary' }
                Headers = @{}
                Query   = @{ tenantFilter = 'contoso.onmicrosoft.com' }
                Body    = @{}
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
    }

    It 'aggregates sizes without returning names' {
        $Response = Invoke-ListSiteRecycleBinSummary -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ListSiteRecycleBinSummary' }
                Headers = @{}
                Query   = @{
                    tenantFilter = 'contoso.onmicrosoft.com'
                    SiteUrl      = 'https://contoso.sharepoint.com/sites/a'
                }
                Body    = @{}
            })

        $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
        $Response.Body.Results.totalBytes | Should -Be 150
        $Response.Body.Results.firstStageBytes | Should -Be 100
        $Response.Body.Results.secondStageBytes | Should -Be 50
        ($Response.Body.Results.PSObject.Properties.Name -contains 'Title') | Should -BeFalse
        ($Response.Body.Results.PSObject.Properties.Name -contains 'LeafName') | Should -BeFalse
    }

    It 'uses skip-based pagination beyond first page' {
        $script:GetRequestCount = 0
        $script:RequestUris = @()
        function global:New-GraphGetRequest {
            param($uri, $tenantid, $scope, $AsApp, $extraHeaders, [switch]$UseCertificate, [bool]$noPagination, [switch]$SkipValueExtraction)
            $script:GetRequestCount++
            $script:RequestUris += $uri
            
            if ($uri -match '\$skip=0') {
                $Items = 1..500 | ForEach-Object { [PSCustomObject]@{ Id = $_; Size = 100; ItemState = 1 } }
                [PSCustomObject]@{ value = @($Items) }
            } elseif ($uri -match '\$skip=500') {
                $Items = 501..550 | ForEach-Object { [PSCustomObject]@{ Id = $_; Size = 100; ItemState = 1 } }
                [PSCustomObject]@{ value = @($Items) }
            } else {
                [PSCustomObject]@{ value = @() }
            }
        }
        
        $Response = Invoke-ListSiteRecycleBinSummary -Request ([pscustomobject]@{
                Params  = @{ CIPPEndpoint = 'ListSiteRecycleBinSummary' }
                Headers = @{}
                Query   = @{
                    tenantFilter = 'contoso.onmicrosoft.com'
                    SiteUrl      = 'https://contoso.sharepoint.com/sites/a'
                    MaxItems     = 600
                }
                Body    = @{}
            })

        $script:GetRequestCount | Should -BeGreaterThan 1
        $Response.Body.Results.itemCount | Should -Be 550
        $Response.Body.Results.capped | Should -BeFalse
        ($script:RequestUris | Where-Object { $_ -match '\$skip=500' }).Count | Should -BeGreaterThan 0
    }
}
