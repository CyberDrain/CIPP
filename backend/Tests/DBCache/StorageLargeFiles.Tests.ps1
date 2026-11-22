# Pester tests for the SharePoint large file scan: Set-CIPPDBCacheStorageLargeFiles (fan-out),
# Push-DBCacheStorageLargeFilesBatch (per-site collection) and Push-StoreStorageLargeFiles (cache write).

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Find = { param($Name) Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name -File | Select-Object -First 1 -ExpandProperty FullName }

    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Test-CIPPStandardLicense { param($StandardName, $TenantFilter, $Preset, [switch]$SkipLog) }
    function Get-CIPPSharePointSiteUsageReport { [CmdletBinding()] param($TenantFilter) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $TableName, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Update-CippQueueEntry { param($RowKey, $TotalTasks, [switch]$IncrementTotalTasks) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp) }
    function Get-CIPPSharePointLibraryContents { param($TenantFilter, $SiteSegment, $ListId, [switch]$LargestFiles, $MaxFiles, $MaxFolders) }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $TableName) }

    . (& $Find 'Set-CIPPDBCacheStorageLargeFiles.ps1')
    . (& $Find 'Push-DBCacheStorageLargeFilesBatch.ps1')
    . (& $Find 'Push-StoreStorageLargeFiles.ps1')
}

Describe 'Set-CIPPDBCacheStorageLargeFiles' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Test-CIPPStandardLicense { $true }
        Mock Add-CIPPDbItem { }
        Mock Update-CippQueueEntry { }
        Mock Start-CIPPOrchestrator { }
    }

    It 'scans only sites holding 1 GB or more, in batches of 10' {
        Mock Get-CIPPSharePointSiteUsageReport {
            foreach ($i in 1..23) { [pscustomobject]@{ webUrl = "https://c.sharepoint.com/sites/big$i"; displayName = "Big $i"; storageUsedInBytes = 5GB } }
            [pscustomobject]@{ webUrl = 'https://c.sharepoint.com/sites/small'; displayName = 'Small'; storageUsedInBytes = 200MB }
            [pscustomobject]@{ webUrl = $null; displayName = 'No address'; storageUsedInBytes = 9GB }
        }

        Set-CIPPDBCacheStorageLargeFiles -TenantFilter 'contoso.com' -QueueId 'q1'

        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly -ParameterFilter {
            $InputObject.Batch.Count -eq 3 -and
            @($InputObject.Batch[0].Sites).Count -eq 10 -and
            @($InputObject.Batch[2].Sites).Count -eq 3 -and
            $InputObject.Batch[0].FunctionName -eq 'DBCacheStorageLargeFilesBatch' -and
            $InputObject.Batch[0].QueueId -eq 'q1' -and
            $InputObject.PostExecution.FunctionName -eq 'StoreStorageLargeFiles' -and
            @($InputObject.Batch.Sites.webUrl) -notcontains 'https://c.sharepoint.com/sites/small' -and
            @($InputObject.Batch.BatchNumber) -join ',' -eq '1,2,3' -and
            @($InputObject.Batch.Sites.webUrl | Select-Object -Unique).Count -eq 23 -and
            @($InputObject.PostExecution.Parameters.ExpectedSiteUrls).Count -eq 23 -and
            $InputObject.PostExecution.Parameters.ExpectedSiteUrls[0] -eq 'https://c.sharepoint.com/sites/big1'
        }
        Should -Invoke Update-CippQueueEntry -Times 1 -Exactly -ParameterFilter { $TotalTasks -eq 3 }
    }

    It 'writes an empty scan when no site is large enough' {
        Mock Get-CIPPSharePointSiteUsageReport { [pscustomobject]@{ webUrl = 'https://c.sharepoint.com/sites/small'; storageUsedInBytes = 1MB } }

        Set-CIPPDBCacheStorageLargeFiles -TenantFilter 'contoso.com'

        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $TableName -eq 'CippStorageLargeFiles' -and $ClearOnEmpty -and @($Data).Count -eq 0 }
    }

    It 'does not scan a site without a usage figure and keeps its earlier files' {
        Mock Get-CIPPSharePointSiteUsageReport {
            [pscustomobject]@{ webUrl = 'https://c.sharepoint.com/sites/big'; displayName = 'Big'; storageUsedInBytes = 5GB }
            [pscustomobject]@{ webUrl = 'https://c.sharepoint.com/sites/new/'; displayName = 'New'; storageUsedInBytes = $null }
        }

        Set-CIPPDBCacheStorageLargeFiles -TenantFilter 'contoso.com'

        Should -Invoke Start-CIPPOrchestrator -Times 1 -Exactly -ParameterFilter {
            (@($InputObject.Batch.Sites.webUrl) -join ',') -eq 'https://c.sharepoint.com/sites/big' -and
            (@($InputObject.PostExecution.Parameters.ExpectedSiteUrls) -join ',') -eq 'https://c.sharepoint.com/sites/big' -and
            (@($InputObject.PostExecution.Parameters.UnmeasuredSiteUrls) -join ',') -eq 'https://c.sharepoint.com/sites/new'
        }
    }

    It 'clears only the sites whose usage figure is too small when no site is large enough' {
        Mock Get-CIPPSharePointSiteUsageReport {
            [pscustomobject]@{ webUrl = 'https://c.sharepoint.com/sites/shrunk'; displayName = 'Shrunk'; storageUsedInBytes = 200MB }
            [pscustomobject]@{ webUrl = 'https://c.sharepoint.com/sites/new'; displayName = 'New'; storageUsedInBytes = $null }
        }
        Mock New-CIPPDbRequest {
            [pscustomobject]@{ rowType = 'File'; id = 'old-shrunk'; siteUrl = 'https://c.sharepoint.com/sites/shrunk' }
            [pscustomobject]@{ rowType = 'File'; id = 'old-new'; siteUrl = 'https://c.sharepoint.com/sites/new' }
        }

        Set-CIPPDBCacheStorageLargeFiles -TenantFilter 'contoso.com'

        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { $ClearOnEmpty -and (@($Data.id) -join ',') -eq 'old-new' }
    }

    It 'fails the run and leaves the earlier scan alone when <Name>' -ForEach @(
        @{ Name = 'the usage report has never been synced'; Usage = { throw 'No SharePoint site listing data found in reporting database. Sync SharePointSiteUsage cache first.' } }
        # The site listing synced but the usage report did not: every row carries a null size.
        @{ Name = 'the sites have no usage figures'; Usage = { [pscustomobject]@{ webUrl = 'https://c.sharepoint.com/sites/big1'; displayName = 'Big 1'; storageUsedInBytes = $null } } }
    ) {
        $Make = $Usage
        Mock Get-CIPPSharePointSiteUsageReport { & $Make }

        { Set-CIPPDBCacheStorageLargeFiles -TenantFilter 'contoso.com' } | Should -Throw '*Run Sync usage on the Storage Report first*'

        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' }
    }
}

Describe 'Push-DBCacheStorageLargeFilesBatch' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock New-GraphGetRequest {
            [pscustomobject]@{ id = 'lib-docs'; displayName = 'Documents'; list = [pscustomobject]@{ template = 'documentLibrary'; hidden = $false } }
            [pscustomobject]@{ id = 'lib-pages'; displayName = 'Site Pages'; list = [pscustomobject]@{ template = 'webPageLibrary'; hidden = $false } }
            [pscustomobject]@{ id = 'lib-hidden'; displayName = 'Form Templates'; list = [pscustomobject]@{ template = 'documentLibrary'; hidden = $true } }
        }
        Mock Get-CIPPSharePointLibraryContents {
            foreach ($i in 1..30) { [pscustomobject]@{ id = "f$i"; driveId = 'b!d'; name = "file$i.mp4"; type = 'File'; folderPath = '/Video'; sizeInBytes = $i * 1MB; archiveStatus = 'active'; lastModifiedDateTime = '2024-01-01T00:00:00Z'; lastModifiedBy = 'Megan Bowen'; webUrl = "https://c.sharepoint.com/sites/a/f$i" } }
            [pscustomobject]@{ id = 'deep'; driveId = 'b!d'; name = 'Deep folder'; type = 'Folder'; sizeInBytes = 900MB }
        }
    }

    It 'keeps the 25 largest files of each site from its document libraries only' {
        $Result = Push-DBCacheStorageLargeFilesBatch -Item @{
            TenantFilter = 'contoso.com'
            BatchNumber  = 2
            Sites        = @(@{ webUrl = 'https://c.sharepoint.com/sites/a/'; displayName = 'Site A' })
        }

        $Result.BatchNumber | Should -Be 2
        $Site = $Result.Sites[0]
        $Site.Status | Should -Be 'Full'
        $Site.Rows.Count | Should -Be 25
        $Site.Rows[0].name | Should -Be 'file30.mp4'
        $Site.Rows[0].rowType | Should -Be 'File'
        $Site.Rows[0].id | Should -Be 'b!d_f30'
        $Site.Rows[0].siteUrl | Should -Be 'https://c.sharepoint.com/sites/a'
        $Site.Rows[0].siteName | Should -Be 'Site A'
        $Site.Rows[0].libraryName | Should -Be 'Documents'
        $Site.Rows.name | Should -Not -Contain 'Deep folder'
        Should -Invoke Get-CIPPSharePointLibraryContents -Times 1 -Exactly -ParameterFilter {
            $ListId -eq 'lib-docs' -and $SiteSegment -eq 'c.sharepoint.com:/sites/a:' -and $LargestFiles -and $MaxFiles -eq 25 -and $MaxFolders -eq 500
        }
    }

    It 'marks every row of a site <Kind>' -ForEach @(
        @{ Kind = 'as fully searched when no folder was left unopened'; Leftover = $false; Expected = $true }
        @{ Kind = 'as not fully searched when the search stopped with a folder unopened'; Leftover = $true; Expected = $false }
    ) {
        $WithFolder = $Leftover
        Mock Get-CIPPSharePointLibraryContents {
            foreach ($i in 1..3) { [pscustomobject]@{ id = "f$i"; driveId = 'b!d'; name = "file$i.mp4"; type = 'File'; folderPath = '/'; sizeInBytes = $i * 1GB; archiveStatus = 'active' } }
            if ($WithFolder) { [pscustomobject]@{ id = 'deep'; driveId = 'b!d'; name = 'Deep folder'; type = 'Folder'; sizeInBytes = 900GB } }
        }

        $Result = Push-DBCacheStorageLargeFilesBatch -Item @{ TenantFilter = 'contoso.com'; BatchNumber = 1; Sites = @(@{ webUrl = 'https://c.sharepoint.com/sites/a' }) }

        @($Result.Sites[0].Rows).Count | Should -Be 3
        @($Result.Sites[0].Rows.searchComplete | Select-Object -Unique) | Should -Be @($Expected)
    }

    It 'returns a site as Skipped when its search stopped early without keeping a file' {
        Mock Get-CIPPSharePointLibraryContents {
            [pscustomobject]@{ id = 'deep'; driveId = 'b!d'; name = 'Deep folder'; type = 'Folder'; sizeInBytes = 900GB }
        }

        $Result = Push-DBCacheStorageLargeFilesBatch -Item @{ TenantFilter = 'contoso.com'; BatchNumber = 1; Sites = @(@{ webUrl = 'https://c.sharepoint.com/sites/a' }) }

        $Result.Sites[0].Status | Should -Be 'Skipped'
        @($Result.Sites[0].Rows).Count | Should -Be 0
    }

    It 'returns a site as read with no rows when its search finished without finding a file' {
        Mock Get-CIPPSharePointLibraryContents { }

        $Result = Push-DBCacheStorageLargeFilesBatch -Item @{ TenantFilter = 'contoso.com'; BatchNumber = 1; Sites = @(@{ webUrl = 'https://c.sharepoint.com/sites/a' }) }

        $Result.Sites[0].Status | Should -Be 'Full'
        @($Result.Sites[0].Rows).Count | Should -Be 0
    }

    It 'returns an unreadable site as Skipped and still reads the rest' {
        Mock New-GraphGetRequest { throw 'Access denied' } -ParameterFilter { $uri -like '*sites/locked*' }

        $Result = Push-DBCacheStorageLargeFilesBatch -Item @{
            TenantFilter = 'contoso.com'
            BatchNumber  = 1
            Sites        = @(@{ webUrl = 'https://c.sharepoint.com/sites/locked' }, @{ webUrl = 'https://c.sharepoint.com/sites/a' })
        }

        $Result.Sites.Status | Should -Be @('Skipped', 'Full')
        @($Result.Sites[0].Rows).Count | Should -Be 0
        $Result.Sites[1].Rows.Count | Should -Be 25
    }
}

Describe 'Push-StoreStorageLargeFiles' {
    BeforeEach {
        Mock Write-LogMessage { }
        Mock Add-CIPPDbItem { }
    }

    It 'writes every collected file once, replacing the previous scan' {
        Mock New-CIPPDbRequest { }

        Push-StoreStorageLargeFiles -Item @{
            Parameters = @{ TenantFilter = 'contoso.com'; ExpectedSiteUrls = @('https://c.sharepoint.com/sites/a', 'https://c.sharepoint.com/sites/c') }
            Results    = @(
                @{ Sites = @(@{ SiteUrl = 'https://c.sharepoint.com/sites/a'; Status = 'Full'; Rows = @(@{ id = 'a' }, @{ id = 'b' }) }) }
                @{ Sites = @(@{ SiteUrl = 'https://c.sharepoint.com/sites/c'; Status = 'Full'; Rows = @(@{ id = 'c' }) }) }
            )
        }

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter {
            $Type -eq 'StorageLargeFiles' -and $TableName -eq 'CippStorageLargeFiles' -and $AddCount -and $ClearOnEmpty -and @($Data).Count -eq 3
        }
        Should -Invoke New-CIPPDbRequest -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Info' }
    }

    It 'keeps the previous files of a site that was skipped or never returned, and warns how many were not read' {
        Mock New-CIPPDbRequest {
            [pscustomobject]@{ rowType = 'File'; id = 'old-a'; siteUrl = 'https://c.sharepoint.com/sites/a' }
            [pscustomobject]@{ rowType = 'File'; id = 'old-locked'; siteUrl = 'https://c.sharepoint.com/sites/locked' }
            [pscustomobject]@{ rowType = 'File'; id = 'old-lost'; siteUrl = 'https://c.sharepoint.com/sites/LOST' }
        }

        Push-StoreStorageLargeFiles -Item @{
            Parameters = @{ TenantFilter = 'contoso.com'; ExpectedSiteUrls = @('https://c.sharepoint.com/sites/a', 'https://c.sharepoint.com/sites/locked', 'https://c.sharepoint.com/sites/lost') }
            Results    = @(
                @{ Sites = @(
                        @{ SiteUrl = 'https://c.sharepoint.com/sites/a'; Status = 'Full'; Rows = @([pscustomobject]@{ id = 'new-a'; siteUrl = 'https://c.sharepoint.com/sites/a' }) }
                        @{ SiteUrl = 'https://c.sharepoint.com/sites/locked'; Status = 'Skipped'; Rows = @() }
                    )
                }
            )
        }

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter {
            (@($Data.id) -join ',') -eq 'new-a,old-locked,old-lost'
        }
        Should -Invoke New-CIPPDbRequest -Times 1 -Exactly -ParameterFilter { $TableName -eq 'CippStorageLargeFiles' -and $Type -eq 'StorageLargeFiles' }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*2 sites could not be read*' }
    }

    It 'fails the run and leaves the previous scan in place when no site could be read' {
        {
            Push-StoreStorageLargeFiles -Item @{
                Parameters = @{ TenantFilter = 'contoso.com'; ExpectedSiteUrls = @('https://c.sharepoint.com/sites/locked') }
                Results    = @(@{ Sites = @(@{ SiteUrl = 'https://c.sharepoint.com/sites/locked'; Status = 'Skipped'; Rows = @() }) })
            }
        } | Should -Throw '*no site could be read*'

        Should -Invoke Add-CIPPDbItem -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $message -like '*no site could be read*' }
    }

    It 'counts a site that came back both read and skipped as read, and writes each file once' {
        Mock New-CIPPDbRequest {
            [pscustomobject]@{ rowType = 'File'; id = 'b!d_old'; siteUrl = 'https://c.sharepoint.com/sites/a' }
            [pscustomobject]@{ rowType = 'File'; id = 'b!d_f1'; siteUrl = 'https://c.sharepoint.com/sites/locked' }
            [pscustomobject]@{ rowType = 'File'; id = 'b!d_old-locked'; siteUrl = 'https://c.sharepoint.com/sites/locked' }
        }
        $A = @{ SiteUrl = 'https://c.sharepoint.com/sites/a'; Status = 'Full'; Rows = @(@{ id = 'b!d_f1'; siteUrl = 'https://c.sharepoint.com/sites/a' }, @{ id = 'b!d_f2'; siteUrl = 'https://c.sharepoint.com/sites/a' }) }

        Push-StoreStorageLargeFiles -Item @{
            Parameters = @{ TenantFilter = 'contoso.com'; ExpectedSiteUrls = @('https://c.sharepoint.com/sites/a', 'https://c.sharepoint.com/sites/locked') }
            Results    = @(
                @{ Sites = @(@{ SiteUrl = 'https://c.sharepoint.com/sites/A'; Status = 'Skipped'; Rows = @() }, @{ SiteUrl = 'https://c.sharepoint.com/sites/locked'; Status = 'Skipped'; Rows = @() }) }
                @{ Sites = @($A) }
                @{ Sites = @($A) }
            )
        }

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { (@($Data.id) -join ',') -eq 'b!d_f1,b!d_f2,b!d_old-locked' }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*1 sites could not be read*1 sites were read*' }
    }

    It 'keeps the previous files of a site that had no usage figure' {
        Mock New-CIPPDbRequest {
            [pscustomobject]@{ rowType = 'File'; id = 'old-new'; siteUrl = 'https://c.sharepoint.com/sites/new' }
            [pscustomobject]@{ rowType = 'File'; id = 'old-gone'; siteUrl = 'https://c.sharepoint.com/sites/gone' }
        }

        Push-StoreStorageLargeFiles -Item @{
            Parameters = @{ TenantFilter = 'contoso.com'; ExpectedSiteUrls = @('https://c.sharepoint.com/sites/a'); UnmeasuredSiteUrls = @('https://c.sharepoint.com/sites/new') }
            Results    = @(@{ Sites = @(@{ SiteUrl = 'https://c.sharepoint.com/sites/a'; Status = 'Full'; Rows = @(@{ id = 'new-a' }) }) })
        }

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { (@($Data.id) -join ',') -eq 'new-a,old-new' }
    }

    It 'writes two files whose ids differ only by case as two rows, and matches site URLs without case' {
        Mock New-CIPPDbRequest {
            [pscustomobject]@{ rowType = 'File'; id = 'b!d_ABC'; siteUrl = 'https://c.sharepoint.com/sites/LOCKED' }
        }

        Push-StoreStorageLargeFiles -Item @{
            Parameters = @{ TenantFilter = 'contoso.com'; ExpectedSiteUrls = @('https://c.sharepoint.com/sites/a', 'https://c.sharepoint.com/sites/locked') }
            Results    = @(@{ Sites = @(
                        @{ SiteUrl = 'https://c.sharepoint.com/sites/a'; Status = 'Full'; Rows = @(@{ id = 'b!d_AbC' }, @{ id = 'b!d_abc' }) }
                        @{ SiteUrl = 'https://c.sharepoint.com/sites/locked'; Status = 'Skipped'; Rows = @() }
                    )
                })
        }

        Should -Invoke Add-CIPPDbItem -Times 1 -Exactly -ParameterFilter { (@($Data.id) -join ',') -ceq 'b!d_AbC,b!d_abc,b!d_ABC' }
    }
}

Describe 'Large file scan code' {
    It '<Name> does not use +=' -ForEach @(
        @{ Name = 'Get-CIPPSharePointLibraryContents.ps1' }
        @{ Name = 'Set-CIPPDBCacheStorageLargeFiles.ps1' }
        @{ Name = 'Push-DBCacheStorageLargeFilesBatch.ps1' }
        @{ Name = 'Push-StoreStorageLargeFiles.ps1' }
    ) {
        $Path = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name -File | Select-Object -First 1 -ExpandProperty FullName
        $Ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$null, [ref]$null)
        $PlusEquals = $Ast.FindAll({ param($Node) $Node -is [System.Management.Automation.Language.AssignmentStatementAst] -and $Node.Operator -eq 'PlusEquals' }, $true)
        @($PlusEquals).Count | Should -Be 0
    }
}
