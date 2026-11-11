BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $FunctionPath = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Push-DBCacheStorageCleanupScanBatch.ps1' -File |
        Select-Object -First 1 -ExpandProperty FullName

    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Get-SharePointAdminLink { param($Public, $tenantFilter) [PSCustomObject]@{ SharePointUrl = 'https://contoso.sharepoint.com' } }
    function New-GraphGetRequest {
        param(
            $uri, $tenantid, $scope, $AsApp, $extraHeaders,
            [switch]$UseCertificate,
            [bool]$noPagination,
            [switch]$SkipValueExtraction
        )
        if ($uri -match '^https://graph\.microsoft\.com/beta/sites/.+/lists\?') { return $script:Lists }
        if ($uri -match "/_api/web/lists\(guid'([^']+)'\)\?") { return $script:ListInfo[$Matches[1]] }
        if ($uri -notmatch '/site/RecycleBin\?') { return @() }
        $Skip = if ($uri -match '\$skip=(\d+)') { [int]$Matches[1] } else { 0 }
        $Top = if ($uri -match '\$top=(\d+)') { [int]$Matches[1] } else { 100 }
        [PSCustomObject]@{ value = @($script:Bin | Select-Object -Skip $Skip -First $Top) }
    }

    . $FunctionPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-SPOAdminListInt64.ps1')
}

Describe 'Push-DBCacheStorageCleanupScanBatch' {
    AfterEach { $script:Lists = $null; $script:ListInfo = $null; $script:Bin = $null }

    It 'records each library''s version policy from its trim mode' {
        $script:Lists = @('off', 'none', 'age', 'auto') | ForEach-Object { [PSCustomObject]@{ id = $_; name = $_; displayName = $_; list = [PSCustomObject]@{ template = 'documentLibrary' } } }
        $Metrics = [PSCustomObject]@{ StorageMetrics = [PSCustomObject]@{ TotalSize = '300'; TotalFileStreamSize = '100'; TotalFileCount = '2' } }
        $script:ListInfo = @{
            off  = [PSCustomObject]@{ EnableVersioning = $false; MajorVersionLimit = 0; VersionPolicies = [PSCustomObject]@{ DefaultTrimMode = 0 }; RootFolder = $Metrics }
            none = [PSCustomObject]@{ EnableVersioning = $true; MajorVersionLimit = 500; VersionPolicies = [PSCustomObject]@{ DefaultTrimMode = 0 }; RootFolder = $Metrics }
            age  = [PSCustomObject]@{ EnableVersioning = $true; MajorVersionLimit = 100; VersionPolicies = [PSCustomObject]@{ DefaultTrimMode = 1; DefaultExpireAfterDays = 365 }; RootFolder = $Metrics }
            auto = [PSCustomObject]@{ EnableVersioning = $true; MajorVersionLimit = 500; VersionPolicies = [PSCustomObject]@{ DefaultTrimMode = 2; DefaultExpireAfterDays = 30 }; RootFolder = $Metrics }
        }
        $Result = Push-DBCacheStorageCleanupScanBatch -Item @{
            TenantFilter = 'contoso.onmicrosoft.com'
            BatchNumber  = 1
            Sites        = @(@{ id = 's1'; displayName = 'A'; webUrl = 'https://contoso.sharepoint.com/sites/a' })
        }

        $Rows = @{}
        foreach ($Row in $Result.Sites[0].Rows) { $Rows[$Row.libraryId] = $Row }
        $Rows.off.versionPolicy | Should -Be 'Versioning off'
        $Rows.none.versionPolicy | Should -Be '500 versions, never expire'
        $Rows.age.versionPolicy | Should -Be '100 versions, expire after 365 days'
        $Rows.auto.versionPolicy | Should -Be 'Automatic'
        $Rows.none.versionTrimMode | Should -Be 0
        $Rows.none.versionEstimateBytes | Should -Be 200
        $Rows.none.fileStreamSizeInBytes | Should -Be 100
    }

    It 'counts every recycle bin item of a bin larger than one page' {
        $script:Bin = @(1..520 | ForEach-Object { [PSCustomObject]@{ Id = "$_"; Size = 10; ItemState = 1 } })
        $Result = Push-DBCacheStorageCleanupScanBatch -Item @{
            TenantFilter = 'contoso.onmicrosoft.com'
            BatchNumber  = 1
            Sites        = @(@{ id = 's1'; displayName = 'A'; webUrl = 'https://contoso.sharepoint.com/sites/a' })
        }

        $Row = $Result.Sites[0].SiteRow
        $Result.Sites[0].CollectionStatus | Should -Be 'Full'
        $Row.recycleItemCount | Should -Be 520
        $Row.recycleTotalBytes | Should -Be 5200
        $Row.recycleScannedItems | Should -Be 520
        $Row.recycleCapped | Should -BeFalse
    }
}
