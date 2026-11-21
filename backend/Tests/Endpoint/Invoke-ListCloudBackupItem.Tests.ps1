BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/CIPPCore/Public/CloudBackup/Get-CIPPCloudBackupOwnerSource.ps1')
    function Get-CIPPCloudBackupOwnerListing { param($Destination, $OwnerPrefix, $AsOf, $Path, $Search, $Type, [string[]]$Key, $ModifiedFrom, $ModifiedTo, [switch]$Recurse, [switch]$IncludeDeleted, [switch]$IncludeFolders, [switch]$Stream, $Skip, $Take) }
    function Get-CIPPCloudBackupObjectVersionList { param($Destination, $Prefix) }
    $script:PolicyId = '11111111-1111-1111-1111-111111111111'
    $script:Prefix = "$($script:PolicyId)/c1/onedrive/u1/"
    function Invoke-ItemRequest {
        param($Query)
        $Base = @{ PolicyId = $script:PolicyId; TenantId = 'contoso.com'; Workload = 'onedrive'; OwnerId = 'u1'; Key = 'items/d1/f1' }
        foreach ($Name in @($Query.Keys)) { $Base[$Name] = $Query[$Name] }
        Invoke-ListCloudBackupItem -Request (New-CloudBackupRequest -Endpoint 'ListCloudBackupItem' -Query $Base)
    }
    function New-Entry {
        param($Key, $Type = 'file', $Deleted = $false)
        [pscustomobject]@{ Key = $Key; Path = 'Documents'; Name = 'a.docx'; Type = $Type; Size = 10; Modified = '2026-11-19T00:00:00Z'; VersionId = 'v2'; Deleted = $Deleted; Extra = [pscustomobject]@{ driveId = 'd1' }; RunStamp = '20261120T000000Z' }
    }
}

Describe 'Invoke-ListCloudBackupItem' {
    BeforeEach {
        $script:Allowed = @('AllTenants')
        $script:PolicyRow = New-CloudBackupPolicyRow
        $script:StateRow = [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'onedrive_u1'; OwnerId = 'u1' }
        $script:Listing = [pscustomobject]@{ RunStamp = '20261120T000000Z'; Total = 1; Items = @(New-Entry -Key 'items/d1/f1'); Folders = @() }
        Mock Test-CIPPAccess { $script:Allowed }
        Mock Get-Tenants { $script:CloudBackupTenants }
        Mock Get-CIPPAzDataTableEntity { $script:PolicyRow } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity { $script:StateRow } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Id = $Id; Provider = 'AzureBlob' } }
        Mock Get-CIPPCloudBackupOwnerListing { $script:Listing }
        Mock Get-CIPPCloudBackupObjectVersionList {
            [pscustomobject]@{ Key = "$($script:Prefix)items/d1/f1"; VersionId = 'v1'; IsLatest = $false; IsDeleteMarker = $false; LastModified = [datetime]::new(2026, 11, 18, 0, 0, 0, [DateTimeKind]::Utc); Size = 8 }
            [pscustomobject]@{ Key = "$($script:Prefix)items/d1/f1"; VersionId = 'v3'; IsLatest = $true; IsDeleteMarker = $true; LastModified = [datetime]::new(2026, 11, 20, 1, 0, 0, [DateTimeKind]::Utc); Size = 0 }
            [pscustomobject]@{ Key = "$($script:Prefix)items/d1/f1"; VersionId = 'v2'; IsLatest = $false; IsDeleteMarker = $false; LastModified = [datetime]::new(2026, 11, 19, 0, 0, 0, [DateTimeKind]::Utc); Size = 10 }
            [pscustomobject]@{ Key = "$($script:Prefix)items/d1/f1.bak"; VersionId = 'x1'; IsLatest = $true; IsDeleteMarker = $false; LastModified = [datetime]::new(2026, 11, 19, 0, 0, 0, [DateTimeKind]::Utc); Size = 1 }
        }
        Mock Write-LogMessage { }
    }

    It 'returns the entry at the point in time with the versions of exactly that key, newest first' {
        $Response = Invoke-ItemRequest -Query @{ AsOf = '20261120T000000Z' }

        $Response.StatusCode | Should -Be 200
        $Response.Body.Key | Should -Be 'items/d1/f1'
        $Response.Body.VersionId | Should -Be 'v2'
        $Response.Body.Deleted | Should -BeFalse
        $Response.Body.Extra.driveId | Should -Be 'd1'
        $Response.Body.RunStamp | Should -Be '20261120T000000Z'
        $Versions = @($Response.Body.Versions)
        @($Versions.VersionId) | Should -Be @('v3', 'v2', 'v1')
        $Versions[0].Deleted | Should -BeTrue
        $Versions[0].At | Should -Be '2026-11-20T01:00:00.0000000Z'
        $Versions[1].Size | Should -Be 10
        Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 1 -Exactly -ParameterFilter { $IncludeDeleted -and $IncludeFolders -and (@($Key) -join ',') -eq 'items/d1/f1' -and $AsOf -eq '20261120T000000Z' -and -not $PesterBoundParameters.ContainsKey('Path') }
        Should -Invoke Get-CIPPCloudBackupObjectVersionList -Times 1 -Exactly -ParameterFilter { $Prefix -eq "$($script:Prefix)items/d1/f1" }
    }

    It 'returns a deleted item with Deleted set' {
        $script:Listing.Items = @(New-Entry -Key 'items/d1/f1' -Deleted $true)
        (Invoke-ItemRequest -Query @{}).Body.Deleted | Should -BeTrue
    }

    It 'returns no versions for a folder' {
        $script:Listing.Items = @(New-Entry -Key 'items/d1/f1' -Type 'folder')
        $Response = Invoke-ItemRequest -Query @{}
        @($Response.Body.Versions).Count | Should -Be 0
        Should -Invoke Get-CIPPCloudBackupObjectVersionList -Times 0 -Exactly
    }

    It 'returns 404 for a key that is not in the backup at that point in time' {
        $script:Listing = [pscustomobject]@{ RunStamp = '20261120T000000Z'; Total = 0; Items = @(); Folders = @() }
        (Invoke-ItemRequest -Query @{ Key = 'items/d1/nope' }).StatusCode | Should -Be 404
        Should -Invoke Get-CIPPCloudBackupObjectVersionList -Times 0 -Exactly
    }

    It 'returns 400 without a Key and 403 for a tenant the caller cannot see' {
        (Invoke-ItemRequest -Query @{ Key = '' }).StatusCode | Should -Be 400
        $script:Allowed = @('c2')
        (Invoke-ItemRequest -Query @{}).StatusCode | Should -Be 403
        Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 0 -Exactly
    }

    It 'returns 500 when the versions cannot be listed' {
        Mock Get-CIPPCloudBackupObjectVersionList { throw 'storage down' }
        (Invoke-ItemRequest -Query @{}).StatusCode | Should -Be 500
    }
}
