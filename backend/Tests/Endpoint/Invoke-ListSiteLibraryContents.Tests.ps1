# Pester tests for Invoke-ListSiteLibraryContents

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $EndpointPath = Join-Path $RepoRoot 'Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions/Teams-Sharepoint/Invoke-ListSiteLibraryContents.ps1'
    if (-not (Test-Path $EndpointPath)) { throw "Could not locate $EndpointPath" }

    class HttpResponseContext {
        [object]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function New-GraphGetRequest { [CmdletBinding()] param($uri, $tenantid, $AsApp) }
    function New-GraphBulkRequest { [CmdletBinding()] param($tenantid, $Requests, $asapp, $Version) }
    function Write-LogMessage { param($Headers, $API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [PSCustomObject]@{ NormalizedError = $Exception.Exception.Message } }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CIPPSharePointLibraryContents.ps1')
    . $EndpointPath
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Get-CippErrorStatusCode.ps1')

    $script:ListId = '11111111-2222-3333-4444-555555555555'
    $script:SiteId = 'contoso.sharepoint.com,aaaaaaaa-0000-0000-0000-000000000001,bbbbbbbb-0000-0000-0000-000000000002'

    function New-TestRequest {
        param([hashtable]$Query)
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ListSiteLibraryContents' }
            Headers = @{}
            Query   = [pscustomobject]$Query
        }
    }

    function New-TestFile {
        param([string]$Id, [long]$Size, [string]$Path = '/drives/drive-1/root:', [string]$ArchiveStatus)
        $File = @{ mimeType = 'video/mp4' }
        if ($ArchiveStatus) { $File['archiveStatus'] = $ArchiveStatus }
        [pscustomobject]@{
            id                   = $Id
            name                 = "$Id.mp4"
            size                 = $Size
            file                 = [pscustomobject]$File
            webUrl               = "https://contoso.sharepoint.com/sites/x/Shared%20Documents/$Id.mp4"
            lastModifiedDateTime = '2026-01-01T00:00:00Z'
            lastModifiedBy       = [pscustomobject]@{ user = [pscustomobject]@{ displayName = 'Megan Bowen' } }
            parentReference      = [pscustomobject]@{ driveId = 'drive-1'; path = $Path }
        }
    }

    function New-TestFolder {
        param([string]$Id, [long]$Size, [int]$ChildCount = 1, [string]$Path = '/drives/drive-1/root:')
        [pscustomobject]@{
            id                   = $Id
            name                 = $Id
            size                 = $Size
            folder               = [pscustomobject]@{ childCount = $ChildCount }
            webUrl               = "https://contoso.sharepoint.com/sites/x/Shared%20Documents/$Id"
            lastModifiedDateTime = '2026-01-01T00:00:00Z'
            lastModifiedBy       = [pscustomobject]@{ user = [pscustomobject]@{ displayName = 'Megan Bowen' } }
            parentReference      = [pscustomobject]@{ driveId = 'drive-1'; path = $Path }
        }
    }
}

Describe 'Invoke-ListSiteLibraryContents' {
    Context 'request validation' {
        BeforeEach {
            Mock New-GraphGetRequest { }
        }

        It 'returns BadRequest for <Name>' -ForEach @(
            @{ Name = 'a missing tenantFilter'; Query = @{ SiteId = 'contoso.sharepoint.com,a,b'; ListId = '11111111-2222-3333-4444-555555555555' } }
            @{ Name = 'a missing ListId'; Query = @{ tenantFilter = 'contoso.com'; SiteId = 'contoso.sharepoint.com,a,b' } }
            @{ Name = 'a ListId that is not a GUID'; Query = @{ tenantFilter = 'contoso.com'; SiteId = 'contoso.sharepoint.com,a,b'; ListId = 'Documents/../x' } }
            @{ Name = 'no SiteId or SiteUrl'; Query = @{ tenantFilter = 'contoso.com'; ListId = '11111111-2222-3333-4444-555555555555' } }
            @{ Name = 'a SiteId with a path in it'; Query = @{ tenantFilter = 'contoso.com'; SiteId = 'contoso.sharepoint.com/../users'; ListId = '11111111-2222-3333-4444-555555555555' } }
            @{ Name = 'a SiteUrl that is not a URL'; Query = @{ tenantFilter = 'contoso.com'; SiteUrl = 'not a url'; ListId = '11111111-2222-3333-4444-555555555555' } }
            @{ Name = 'a FolderId with a path in it'; Query = @{ tenantFilter = 'contoso.com'; SiteId = 'contoso.sharepoint.com,a,b'; ListId = '11111111-2222-3333-4444-555555555555'; FolderId = 'abc/children' } }
            @{ Name = 'AllTenants'; Query = @{ tenantFilter = 'AllTenants'; SiteId = 'contoso.sharepoint.com,a,b'; ListId = '11111111-2222-3333-4444-555555555555' } }
        ) {
            $Response = Invoke-ListSiteLibraryContents -Request (New-TestRequest -Query $Query)

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::BadRequest)
            Should -Invoke New-GraphGetRequest -Times 0 -Exactly
        }
    }

    Context 'listing a folder' {
        It 'lists the top of the library with sizes and archive status' {
            Mock New-GraphGetRequest {
                New-TestFolder -Id 'Videos' -Size 5000 -ChildCount 12
                New-TestFile -Id 'active' -Size 300
                New-TestFile -Id 'cold' -Size 200 -ArchiveStatus 'fullyArchived' -Path '/drives/drive-1/root:/Old%20Projects/2019'
            }

            $Response = Invoke-ListSiteLibraryContents -Request (New-TestRequest -Query @{ tenantFilter = 'contoso.com'; SiteId = $script:SiteId; ListId = $script:ListId })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $Response.Body.Count | Should -Be 3
            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter {
                $uri -like "https://graph.microsoft.com/beta/sites/$($script:SiteId)/lists/$($script:ListId)/drive/root/children?*" -and $tenantid -eq 'contoso.com' -and $AsApp -eq $true
            }

            $Folder = $Response.Body | Where-Object id -EQ 'Videos'
            $Folder.type | Should -Be 'Folder'
            $Folder.sizeInBytes | Should -Be 5000
            $Folder.itemCount | Should -Be 12
            $Folder.archiveStatus | Should -BeNullOrEmpty
            $Folder.driveId | Should -Be 'drive-1'
            $Folder.folderPath | Should -Be '/'

            $Active = $Response.Body | Where-Object id -EQ 'active'
            $Active.type | Should -Be 'File'
            $Active.archiveStatus | Should -Be 'active'
            $Active.lastModifiedBy | Should -Be 'Megan Bowen'

            $Cold = $Response.Body | Where-Object id -EQ 'cold'
            $Cold.archiveStatus | Should -Be 'archived'
            $Cold.folderPath | Should -Be '/Old Projects/2019'
        }

        It 'reports Microsoft Graph archive status <Graph> as <Expected>' -ForEach @(
            @{ Graph = $null; Expected = 'active' }
            @{ Graph = 'notArchived'; Expected = 'active' }
            @{ Graph = 'fullyArchived'; Expected = 'archived' }
            @{ Graph = 'reactivating'; Expected = 'reactivating' }
            @{ Graph = 'unknownFutureValue'; Expected = 'unknown' }
        ) {
            $Status = $Graph
            Mock New-GraphGetRequest { New-TestFile -Id 'one' -Size 1 -ArchiveStatus $Status }

            $Response = Invoke-ListSiteLibraryContents -Request (New-TestRequest -Query @{ tenantFilter = 'contoso.com'; SiteId = $script:SiteId; ListId = $script:ListId })

            @($Response.Body)[0].archiveStatus | Should -BeExactly $Expected
        }

        It 'lists the chosen folder when FolderId is sent' {
            Mock New-GraphGetRequest { New-TestFile -Id 'one' -Size 1 }

            $Response = Invoke-ListSiteLibraryContents -Request (New-TestRequest -Query @{ tenantFilter = 'contoso.com'; SiteId = $script:SiteId; ListId = $script:ListId; FolderId = '01ABCDEF' })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/drive/items/01ABCDEF/children?*' }
        }

        It 'addresses the site by its URL when no SiteId is sent' {
            Mock New-GraphGetRequest { New-TestFile -Id 'one' -Size 1 }

            $null = Invoke-ListSiteLibraryContents -Request (New-TestRequest -Query @{ tenantFilter = 'contoso.com'; SiteUrl = 'https://contoso.sharepoint.com/sites/Projects/'; ListId = $script:ListId })

            Should -Invoke New-GraphGetRequest -Times 1 -Exactly -ParameterFilter {
                $uri -like "https://graph.microsoft.com/beta/sites/contoso.sharepoint.com:/sites/Projects:/lists/$($script:ListId)/drive/root/children?*"
            }
        }

        It 'returns an empty list for an empty folder' {
            Mock New-GraphGetRequest { }

            $Response = Invoke-ListSiteLibraryContents -Request (New-TestRequest -Query @{ tenantFilter = 'contoso.com'; SiteId = $script:SiteId; ListId = $script:ListId })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($Response.Body).Count | Should -Be 0
        }

        It 'returns InternalServerError when Microsoft Graph fails' {
            Mock New-GraphGetRequest { throw 'Graph 503' }

            $Response = Invoke-ListSiteLibraryContents -Request (New-TestRequest -Query @{ tenantFilter = 'contoso.com'; SiteId = $script:SiteId; ListId = $script:ListId })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
            $Response.Body | Should -BeLike 'Failed to list the library contents*'
        }
    }

    Context 'finding the largest files' {
        It 'only opens folders that can still hold a larger file' {
            Mock New-GraphGetRequest {
                foreach ($i in 1..50) { New-TestFile -Id "file$i" -Size 100 }
                New-TestFolder -Id 'Big' -Size 5000 -ChildCount 2
                New-TestFolder -Id 'Small' -Size 60 -ChildCount 3
                New-TestFolder -Id 'Empty' -Size 9000 -ChildCount 0
            }
            Mock New-GraphBulkRequest {
                foreach ($Item in $Requests) {
                    [pscustomobject]@{
                        id     = $Item.id
                        status = 200
                        body   = [pscustomobject]@{ value = @(
                                (New-TestFile -Id 'huge' -Size 4000 -Path '/drives/drive-1/root:/Big'),
                                (New-TestFile -Id 'tiny' -Size 1 -Path '/drives/drive-1/root:/Big')
                            )
                        }
                    }
                }
            }

            $Response = Invoke-ListSiteLibraryContents -Request (New-TestRequest -Query @{ tenantFilter = 'contoso.com'; SiteId = $script:SiteId; ListId = $script:ListId; LargestFiles = 'true' })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            $Response.Body.Count | Should -Be 50
            ($Response.Body | Sort-Object sizeInBytes -Descending)[0].id | Should -Be 'huge'
            $Response.Body.id | Should -Not -Contain 'tiny'
            $Response.Body.type | Select-Object -Unique | Should -Be 'File'
            Should -Invoke New-GraphBulkRequest -Times 1 -Exactly -ParameterFilter {
                @($Requests).Count -eq 1 -and $Requests[0].url -like 'drives/drive-1/items/Big/children?*'
            }
        }

        It 'finds a large file many folders down and stops once no folder can hold a larger one' {
            # Level1 to Level6 each hold one small file; the 600 GB recording sits in Level6, below any fixed depth.
            Mock New-GraphGetRequest {
                foreach ($i in 1..50) { New-TestFile -Id "top$i" -Size 100 }
                New-TestFolder -Id 'Level1' -Size 700
                New-TestFolder -Id 'Tiny' -Size 50
            }
            Mock New-GraphBulkRequest {
                foreach ($Item in $Requests) {
                    $Depth = [int]($Item.id -replace 'Level')
                    $Value = if ($Depth -lt 6) {
                        @((New-TestFolder -Id "Level$($Depth + 1)" -Size (700 - $Depth * 10)), (New-TestFile -Id "small$Depth" -Size 5))
                    } else {
                        @(New-TestFile -Id 'recording' -Size 600 -Path '/drives/drive-1/root:/Level1/Level2/Level3/Level4/Level5/Level6')
                    }
                    [pscustomobject]@{ id = $Item.id; status = 200; body = [pscustomobject]@{ value = $Value } }
                }
            }

            $Response = Invoke-ListSiteLibraryContents -Request (New-TestRequest -Query @{ tenantFilter = 'contoso.com'; SiteId = $script:SiteId; ListId = $script:ListId; LargestFiles = 'true' })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            @($Response.Body)[0].id | Should -Be 'recording'
            @($Response.Body)[0].folderPath | Should -Be '/Level1/Level2/Level3/Level4/Level5/Level6'
            @($Response.Body).Count | Should -Be 50
            @($Response.Body.type | Select-Object -Unique) | Should -Be @('File')
            Should -Invoke New-GraphBulkRequest -Times 6 -Exactly
            Should -Invoke New-GraphBulkRequest -Times 0 -Exactly -ParameterFilter { @($Requests).url -like '*/items/Tiny/*' }
        }

        It 'returns the folders it did not open when it reaches its folder limit' {
            Mock New-GraphGetRequest { New-TestFolder -Id 'Level1' -Size 1000 }
            Mock New-GraphBulkRequest {
                foreach ($Item in $Requests) {
                    $Next = 'Level{0}' -f ([int]($Item.id -replace 'Level') + 1)
                    [pscustomobject]@{
                        id     = $Item.id
                        status = 200
                        body   = [pscustomobject]@{ value = @(
                                (New-TestFolder -Id $Next -Size 900),
                                (New-TestFile -Id "file-$($Item.id)" -Size 10)
                            )
                        }
                    }
                }
            }

            $Response = Invoke-ListSiteLibraryContents -Request (New-TestRequest -Query @{ tenantFilter = 'contoso.com'; SiteId = $script:SiteId; ListId = $script:ListId; LargestFiles = 'true' })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::OK)
            ($Response.Body | Where-Object type -EQ 'Folder').id | Should -Be 'Level61'
            @($Response.Body | Where-Object type -EQ 'File').Count | Should -Be 50
            Should -Invoke New-GraphBulkRequest -Times 60 -Exactly
        }

        It 'keeps the folders waiting to be opened bounded and drops those that can no longer hold a larger file' {
            Mock New-GraphGetRequest {
                New-TestFolder -Id 'Tiny' -Size 50
                foreach ($i in 1..100) { New-TestFolder -Id "Folder$i" -Size (1000 + $i) }
                foreach ($i in 1..50) { New-TestFile -Id "file$i" -Size 100 }
            }
            $script:Waiting = [System.Collections.Generic.List[object]]::new()
            Mock New-GraphBulkRequest {
                # The function's own queue, read from the caller's scope.
                $Queue = Get-Variable -Name Pending -ValueOnly
                $script:Waiting.Add([pscustomobject]@{ Count = $Queue.Count; Ids = @(foreach ($Entry in $Queue.UnorderedItems) { $Entry.Element.id }) })
                foreach ($Item in $Requests) { [pscustomobject]@{ id = $Item.id; status = 200; body = [pscustomobject]@{ value = @() } } }
            }

            $Rows = @(Get-CIPPSharePointLibraryContents -TenantFilter 'contoso.com' -SiteSegment $script:SiteId -ListId $script:ListId -LargestFiles -MaxFiles 50 -MaxFolders 10)

            @($Rows.Where({ $_.type -eq 'File' })).Count | Should -Be 50
            @($Rows.Where({ $_.type -eq 'Folder' }).id) | Should -Be @(foreach ($i in 90..71) { "Folder$i" })
            $script:Waiting.Count | Should -BeGreaterThan 0
            # 10 folders to open and 20 to return at most, of which the first 10 are already being opened.
            $script:Waiting[0].Count | Should -BeLessOrEqual 20
            foreach ($Snapshot in $script:Waiting) { $Snapshot.Ids | Should -Not -Contain 'Tiny' }
        }

        It 'returns InternalServerError when <Name>' -ForEach @(
            @{ Name = 'a later page of a folder failed'; Reply = { [pscustomobject]@{ id = 'Big'; status = 200; PagingIncomplete = $true; PagingError = 'continuation page returned 503'; body = [pscustomobject]@{ value = @() } } } }
            @{ Name = 'a folder got no reply'; Reply = { } }
        ) {
            $Make = $Reply
            Mock New-GraphGetRequest { New-TestFolder -Id 'Big' -Size 1000 }
            Mock New-GraphBulkRequest { & $Make }

            $Response = Invoke-ListSiteLibraryContents -Request (New-TestRequest -Query @{ tenantFilter = 'contoso.com'; SiteId = $script:SiteId; ListId = $script:ListId; LargestFiles = 'true' })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        }

        It 'returns InternalServerError when a folder cannot be read' {
            Mock New-GraphGetRequest { New-TestFolder -Id 'Locked' -Size 1000 }
            Mock New-GraphBulkRequest {
                [pscustomobject]@{ id = 'Locked'; status = 404; body = [pscustomobject]@{ error = [pscustomobject]@{ message = 'itemNotFound' } } }
            }

            $Response = Invoke-ListSiteLibraryContents -Request (New-TestRequest -Query @{ tenantFilter = 'contoso.com'; SiteId = $script:SiteId; ListId = $script:ListId; LargestFiles = 'true' })

            $Response.StatusCode | Should -Be ([System.Net.HttpStatusCode]::InternalServerError)
        }
    }
}
