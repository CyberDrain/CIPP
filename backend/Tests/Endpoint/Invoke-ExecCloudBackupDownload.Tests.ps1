BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    . (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules/CIPPCore/Public/CloudBackup/Resolve-CIPPCloudBackupJobSource.ps1')
    function Get-CIPPCloudBackupRecoveryPoint { param($Destination, $OwnerPrefix) }
    function Read-CIPPCloudBackupObjectPart { param($Destination, $Key, $VersionId, $Part, $PartSize) }
    function Get-CIPPCloudBackupObjectVersionList { param($Destination, $Prefix) }
    function Get-CIPPCloudBackupOwnerListing { param($Destination, $OwnerPrefix, $AsOf, [string[]]$Key, [switch]$IncludeDeleted, [switch]$Stream) }

    $script:PolicyId = '11111111-1111-1111-1111-111111111111'
    $script:Prefix = "$($script:PolicyId)/c1/exchange/u1/"
    function Invoke-Download {
        param([hashtable]$Query)
        Invoke-ExecCloudBackupDownload -Request (New-CloudBackupRequest -Endpoint 'ExecCloudBackupDownload' -Query $Query)
    }
    function New-ItemQuery {
        param([hashtable]$Extra = @{})
        $Query = @{ PolicyId = $script:PolicyId; TenantId = 'contoso.com'; Workload = 'exchange'; OwnerId = 'u1'; Key = 'items/f/m1.fts'; VersionId = 'fts-2'; Name = 'Quarterly "plan": Q4' }
        foreach ($Name in $Extra.PSBase.Keys) { $Query[$Name] = $Extra[$Name] }
        $Query
    }
}

Describe 'Invoke-ExecCloudBackupDownload' {
    BeforeEach {
        $script:Allowed = @('AllTenants')
        $script:Job = [pscustomobject]@{
            PartitionKey = 'CloudBackupJob'; RowKey = 'aaaaaaaa-0000-0000-0000-000000000001'; Type = 'Export'; Status = 'Completed'; PolicyId = $script:PolicyId; Workload = 'onedrive'
            SourceTenantId = 'c1'; SourceTenant = 'contoso.com'; SourceOwnerId = 'u1'; SourceOwnerName = 'User One'; RunStamp = '20261101T000000Z'
            ExportKey = "$($script:PolicyId)/exports/aaaaaaaa-0000-0000-0000-000000000001.zip"; ExpiresAt = [datetime]::UtcNow.AddDays(3).ToString('o'); ExportRemovedAt = ''
        }
        $script:StateRow = [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_u1'; OwnerId = 'u1'; OwnerType = 'UserMailbox'; LastRunId = '' }
        $script:Versions = @(
            [pscustomobject]@{ Key = "$($script:Prefix)items/f/m1.fts"; VersionId = 'fts-1'; IsLatest = $false; IsDeleteMarker = $false; LastModified = '2026-11-01T00:00:01Z' }
            [pscustomobject]@{ Key = "$($script:Prefix)items/f/m1.eml"; VersionId = 'eml-1'; IsLatest = $false; IsDeleteMarker = $false; LastModified = '2026-11-01T00:00:02Z' }
            [pscustomobject]@{ Key = "$($script:Prefix)items/f/m1.fts"; VersionId = 'fts-2'; IsLatest = $true; IsDeleteMarker = $false; LastModified = '2026-11-02T00:00:01Z' }
            [pscustomobject]@{ Key = "$($script:Prefix)items/f/m1.eml"; VersionId = 'eml-2'; IsLatest = $false; IsDeleteMarker = $false; LastModified = '2026-11-02T00:00:03Z' }
            [pscustomobject]@{ Key = "$($script:Prefix)items/f/m1.eml"; VersionId = 'eml-2b'; IsLatest = $true; IsDeleteMarker = $false; LastModified = '2026-11-02T00:00:09Z' }
        )
        Mock Test-CIPPAccess { $script:Allowed }
        Mock Get-Tenants { $script:CloudBackupTenants }
        Mock Get-CIPPCloudBackupPolicy { [pscustomobject]@{ Id = $script:PolicyId; Name = 'Nightly'; DestinationId = '22222222-2222-2222-2222-222222222222' } }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Provider = 'AzureBlob' } }
        Mock Get-CIPPAzDataTableEntity { $script:Job } -ParameterFilter { $TableName -eq 'CloudBackupJobs' }
        Mock Get-CIPPAzDataTableEntity { $script:StateRow } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Read-CIPPCloudBackupObjectPart { [pscustomobject]@{ Body = [byte[]](1, 2, 3); Part = $Part; Parts = 3; Size = [int64]40000000; ContentType = 'application/octet-stream' } }
        Mock Get-CIPPCloudBackupObjectVersionList { $script:Versions }
        Mock Get-CIPPCloudBackupOwnerListing { }
        Mock Write-LogMessage { }
    }

    It 'returns 400 for <Name>' -ForEach @(
        @{ Name = 'a bad part'; Query = @{ JobId = 'aaaaaaaa-0000-0000-0000-000000000001'; Part = '-1' } }
        @{ Name = 'a part that is not a number'; Query = @{ JobId = 'aaaaaaaa-0000-0000-0000-000000000001'; Part = 'x' } }
        @{ Name = 'a bad job id'; Query = @{ JobId = 'nope' } }
        @{ Name = 'nothing to download'; Query = @{} }
        @{ Name = 'a key outside the owner'; Query = @{ PolicyId = '11111111-1111-1111-1111-111111111111'; TenantId = 'c1'; Workload = 'onedrive'; OwnerId = 'u1'; Key = 'files/../../other/x' } }
        @{ Name = 'an index file'; Query = @{ PolicyId = '11111111-1111-1111-1111-111111111111'; TenantId = 'c1'; Workload = 'onedrive'; OwnerId = 'u1'; Key = 'index/20261101T000000Z-00000.jsonl.gz' } }
    ) {
        (Invoke-Download -Query $Query).StatusCode | Should -Be 400
        Should -Invoke Read-CIPPCloudBackupObjectPart -Times 0 -Exactly
    }

    Context 'Export zip' {
        It 'sends a part of the zip with its file name and part headers, and logs the first part only' {
            $Response = Invoke-Download -Query @{ JobId = 'aaaaaaaa-0000-0000-0000-000000000001' }

            $Response.StatusCode | Should -Be 200
            $Response.ContentType | Should -Be 'application/zip'
            $Response.Body | Should -BeOfType [byte]
            $Response.Headers['Content-Disposition'] | Should -Be "attachment; filename=`"User One-onedrive-20261101T000000Z.zip`"; filename*=UTF-8''User%20One-onedrive-20261101T000000Z.zip"
            $Response.Headers['X-CIPP-Download-Parts'] | Should -Be '3'
            $Response.Headers['X-CIPP-Download-Size'] | Should -Be '40000000'
            $Response.Headers['Cache-Control'] | Should -Be 'no-store'
            Should -Invoke Read-CIPPCloudBackupObjectPart -Times 1 -Exactly -ParameterFilter { $Key -eq $script:Job.ExportKey -and $Part -eq 0 }
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $API -eq 'CloudBackupRestore' -and $message -like 'Downloaded export*' }

            (Invoke-Download -Query @{ JobId = 'aaaaaaaa-0000-0000-0000-000000000001'; Part = '2' }).Headers['X-CIPP-Download-Part'] | Should -Be '2'
            Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $API -eq 'CloudBackupRestore' }
        }

        It 'returns <Status> for <Name>' -ForEach @(
            @{ Name = 'an unknown job'; Change = { $script:Job = $null }; Status = 404 }
            @{ Name = 'a restore job'; Change = { $script:Job.Type = 'Restore' }; Status = 404 }
            @{ Name = 'an export still running'; Change = { $script:Job.Status = 'Running' }; Status = 400 }
            @{ Name = 'an expired export'; Change = { $script:Job.ExpiresAt = [datetime]::UtcNow.AddMinutes(-1).ToString('o') }; Status = 404 }
            @{ Name = 'a removed export'; Change = { $script:Job.ExportRemovedAt = '2026-11-10T00:00:00Z' }; Status = 404 }
            @{ Name = 'another tenant'; Change = { $script:Allowed = @('c2') }; Status = 403 }
            @{ Name = 'a zip missing in the destination'; Change = { Mock Read-CIPPCloudBackupObjectPart { } }; Status = 404 }
        ) {
            & $Change
            (Invoke-Download -Query @{ JobId = 'aaaaaaaa-0000-0000-0000-000000000001' }).StatusCode | Should -Be $Status
        }
    }

    Context 'Single items' {
        It 'sends the .eml stored with the requested version of a mail item' {
            $Response = Invoke-Download -Query (New-ItemQuery)

            $Response.StatusCode | Should -Be 200
            $Response.ContentType | Should -Be 'message/rfc822'
            $Response.Headers['Content-Disposition'] | Should -BeLike 'attachment; filename="Quarterly _plan__ Q4.eml"*'
            Should -Invoke Get-CIPPCloudBackupObjectVersionList -Times 1 -Exactly -ParameterFilter { $Prefix -eq "$($script:Prefix)items/f/m1." }
            Should -Invoke Read-CIPPCloudBackupObjectPart -Times 1 -Exactly -ParameterFilter { $Key -eq "$($script:Prefix)items/f/m1.eml" -and $VersionId -eq 'eml-2' }

            $null = Invoke-Download -Query (New-ItemQuery -Extra @{ VersionId = 'fts-1' })
            Should -Invoke Read-CIPPCloudBackupObjectPart -Times 1 -Exactly -ParameterFilter { $VersionId -eq 'eml-1' }
        }

        It 'sends JSON for a mailbox item without an .eml' {
            $script:Versions = @($script:Versions).Where({ $_.Key -like '*.fts' })
            Mock Get-CIPPCloudBackupOwnerListing { [pscustomobject]@{ Key = 'items/f/m1.fts'; Path = 'Calendar'; Name = 'Meeting'; Type = 'event'; Size = 10; Modified = '2026-11-01'; Extra = [pscustomobject]@{ id = 'e1' } } }

            $Response = Invoke-Download -Query (New-ItemQuery -Extra @{ AsOf = '20261101T000000Z'; Name = 'Meeting' })

            $Response.StatusCode | Should -Be 200
            $Response.ContentType | Should -Be 'application/json'
            $Json = [System.Text.Encoding]::UTF8.GetString($Response.Body) | ConvertFrom-Json
            $Json.Name | Should -Be 'Meeting'
            $Json.Details.id | Should -Be 'e1'
            $Response.Headers['X-CIPP-Download-Parts'] | Should -Be '1'
            Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 1 -Exactly -ParameterFilter { $AsOf -eq '20261101T000000Z' -and @($Key) -contains 'items/f/m1.fts' -and $Stream }
            Should -Invoke Read-CIPPCloudBackupObjectPart -Times 0 -Exactly
        }

        It 'sends a file as stored and returns 404 for a missing version' {
            $Response = Invoke-Download -Query (New-ItemQuery -Extra @{ Workload = 'onedrive'; Key = 'files/abc'; VersionId = 'v7'; Name = 'Report.xlsx' })
            $Response.StatusCode | Should -Be 200
            $Response.ContentType | Should -Be 'application/octet-stream'
            Should -Invoke Read-CIPPCloudBackupObjectPart -Times 1 -Exactly -ParameterFilter { $Key -eq "$($script:PolicyId)/c1/onedrive/u1/files/abc" -and $VersionId -eq 'v7' }

            Mock Read-CIPPCloudBackupObjectPart { }
            (Invoke-Download -Query (New-ItemQuery -Extra @{ Workload = 'onedrive'; Key = 'files/abc' })).StatusCode | Should -Be 404
        }

        It 'returns 403 for a tenant the caller cannot access and 404 for an owner without a backup' {
            $script:Allowed = @('c2')
            (Invoke-Download -Query (New-ItemQuery)).StatusCode | Should -Be 403
            $script:Allowed = @('AllTenants')
            $script:StateRow = $null
            (Invoke-Download -Query (New-ItemQuery)).StatusCode | Should -Be 404
        }
    }
}
