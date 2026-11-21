BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/CIPPCore/Public/CloudBackup/Get-CIPPCloudBackupOwnerSource.ps1')
    function Get-CIPPCloudBackupOwnerListing { param($Destination, $OwnerPrefix, $AsOf, $Path, $Search, $Type, [string[]]$Key, $ModifiedFrom, $ModifiedTo, [switch]$Recurse, [switch]$IncludeDeleted, [switch]$IncludeFolders, [switch]$Stream, $Skip, $Take) }
    $script:PolicyId = '11111111-1111-1111-1111-111111111111'
    function Invoke-Items {
        param($Query)
        $Base = @{ PolicyId = $script:PolicyId; TenantId = 'c1'; Workload = 'exchange'; OwnerId = 'u1' }
        foreach ($Name in @($Query.Keys)) { $Base[$Name] = $Query[$Name] }
        Invoke-ListCloudBackupItems -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupItems' -Query $Base)
    }
}

Describe 'Invoke-ListCloudBackupItems' {
    BeforeEach {
        $script:Allowed = @('AllTenants')
        $script:PolicyRow = New-CloudBackupPolicyRow
        $script:StateRow = [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_u1'; OwnerId = 'u1' }
        $script:Listing = [pscustomobject]@{
            RunStamp = '20261120T000000Z'
            Total    = 42
            Items    = @([pscustomobject]@{ Key = 'items/inbox/m1.fts'; Path = 'Inbox'; Name = 'Hello'; Type = 'message'; Size = 300; Modified = '2026-11-19T10:00:00Z'; VersionId = 'v1'; Deleted = $false; Extra = [pscustomobject]@{ from = 'a@b.c'; eml = 'items/inbox/m1.eml' }; RunStamp = '20261120T000000Z' })
            Folders  = @([pscustomobject]@{ Key = 'folders/f2/'; Path = 'Inbox/Projects'; Name = 'Projects'; Type = 'folder'; Extra = $null })
        }
        Mock Test-CIPPAccess { $script:Allowed }
        Mock Get-Tenants { $script:CloudBackupTenants }
        Mock Get-CIPPAzDataTableEntity { $script:PolicyRow } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity { $script:StateRow } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Id = $Id; Provider = 'S3' } }
        Mock Get-CIPPCloudBackupOwnerListing { $script:Listing }
        Mock Write-LogMessage { }
    }

    It 'returns the page of items and the subfolders at the latest point in time by default' {
        $Before = [datetime]::UtcNow
        $Response = Invoke-Items -Query @{}

        $Response.StatusCode | Should -Be 200
        $Response.Body.RunStamp | Should -Be '20261120T000000Z'
        $Response.Body.Total | Should -Be 42
        $Item = @($Response.Body.Items)[0]
        $Item.Key | Should -Be 'items/inbox/m1.fts'
        $Item.VersionId | Should -Be 'v1'
        $Item.Extra.from | Should -Be 'a@b.c'
        @($Item.PSObject.Properties.Name) | Should -Be @('Key', 'Path', 'Name', 'Type', 'Size', 'Modified', 'VersionId', 'Extra')
        $Folder = @($Response.Body.Folders)[0]
        @($Folder.PSObject.Properties.Name) | Should -Be @('Key', 'Path', 'Name')
        $Folder.Path | Should -Be 'Inbox/Projects'
        Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 1 -Exactly -ParameterFilter {
            $OwnerPrefix -eq "$($script:PolicyId)/c1/exchange/u1/" -and $AsOf -is [datetime] -and $AsOf -ge $Before.AddSeconds(-1) -and
            $Skip -eq 0 -and $Take -eq 100 -and $PesterBoundParameters.ContainsKey('Path') -and $PesterBoundParameters['Path'] -eq '' -and -not $PesterBoundParameters.ContainsKey('Search') -and -not $IncludeDeleted
        }
    }

    It 'passes the point in time, folder, search, types and paging on' {
        Invoke-Items -Query @{ AsOf = '20261119T040000Z'; Path = 'Inbox/Projects'; Search = 'invoice'; Type = 'message, event'; Skip = '200'; Take = '50' } | Out-Null

        Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 1 -Exactly -ParameterFilter {
            $AsOf -eq '20261119T040000Z' -and $Path -eq 'Inbox/Projects' -and $Search -eq 'invoice' -and (@($Type) -join ',') -eq 'message,event' -and $Skip -eq 200 -and $Take -eq 50 -and $Recurse
        }
    }

    It 'filters by modified dates and searches below the folder' {
        Invoke-Items -Query @{ Path = 'Inbox'; DateFrom = '2026-11-01'; DateTo = '2026-11-10T12:00:00+01:00' } | Out-Null
        Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 1 -Exactly -ParameterFilter {
            $Recurse -and $Path -eq 'Inbox' -and $ModifiedFrom -eq [datetime]::new(2026, 11, 1, 0, 0, 0, [DateTimeKind]::Utc) -and $ModifiedTo -eq [datetime]::new(2026, 11, 10, 11, 0, 0, [DateTimeKind]::Utc)
        }
    }

    It 'searches the whole backup when searching without a folder' {
        Invoke-Items -Query @{ Search = 'invoice' } | Out-Null
        Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 1 -Exactly -ParameterFilter { -not $PesterBoundParameters.ContainsKey('Path') -and $Search -eq 'invoice' }
    }

    It 'lists only the direct children of a folder when not searching' {
        Invoke-Items -Query @{ Path = 'Inbox' } | Out-Null
        Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 1 -Exactly -ParameterFilter { $Path -eq 'Inbox' -and -not $Recurse }
    }

    It 'converts a date and time AsOf to UTC' {
        Invoke-Items -Query @{ AsOf = '2026-11-19T12:00:00+02:00' } | Out-Null
        Should -Invoke Get-CIPPCloudBackupOwnerListing -ParameterFilter { $AsOf -is [datetime] -and $AsOf -eq [datetime]::new(2026, 11, 19, 10, 0, 0, [DateTimeKind]::Utc) }
    }

    It 'returns 400 for <Case>' -ForEach @(
        @{ Case = 'a bad AsOf'; Query = @{ AsOf = 'yesterday-ish' } }
        @{ Case = 'a negative Skip'; Query = @{ Skip = '-1' } }
        @{ Case = 'a Take over 500'; Query = @{ Take = '501' } }
        @{ Case = 'a Take of 0'; Query = @{ Take = '0' } }
        @{ Case = 'a Take that is not a number'; Query = @{ Take = 'many' } }
        @{ Case = 'a missing OwnerId'; Query = @{ OwnerId = '' } }
        @{ Case = 'a bad DateFrom'; Query = @{ DateFrom = 'soon' } }
    ) {
        (Invoke-Items -Query $Query).StatusCode | Should -Be 400
        Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 0 -Exactly
    }

    It 'returns 404 when the owner has no backup at that point in time' {
        $script:Listing = [pscustomobject]@{ RunStamp = $null; Total = 0; Items = @(); Folders = @() }
        (Invoke-Items -Query @{ AsOf = '20200101T000000Z' }).StatusCode | Should -Be 404
    }

    It 'returns 404 for an owner that was never backed up and 403 for a tenant the caller cannot see' {
        $script:StateRow = $null
        (Invoke-Items -Query @{}).StatusCode | Should -Be 404
        $script:Allowed = @('c3')
        (Invoke-Items -Query @{}).StatusCode | Should -Be 403
        Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 0 -Exactly
    }

    It 'makes no writes to storage or tables' {
        Mock Add-CIPPAzDataTableEntity { }
        Mock Send-CIPPCloudBackupObjectStream { }
        Mock Remove-CIPPCloudBackupObject { }
        Invoke-Items -Query @{} | Out-Null
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Send-CIPPCloudBackupObjectStream -Times 0 -Exactly
        Should -Invoke Remove-CIPPCloudBackupObject -Times 0 -Exactly
    }
}
