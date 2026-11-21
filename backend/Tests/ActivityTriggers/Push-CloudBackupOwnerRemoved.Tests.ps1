BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    function Get-CIPPCloudBackupOwnerListing { param($Destination, $OwnerPrefix, $AsOf, $Path, $Search, $Type, [string[]]$Key, $ModifiedFrom, $ModifiedTo, [switch]$Recurse, [switch]$IncludeDeleted, [switch]$IncludeFolders, [switch]$Stream, $Skip, $Take) }
    function Invoke-CIPPCloudBackupIndexCompaction { param($Destination, $OwnerPrefix, $KeyId, $Key, $MinParts, $MaxAgeDays, $DeletedBefore) }
    function Remove-CIPPCloudBackupIndexHistory { param($Destination, $OwnerPrefix, $OlderThan) }
    $script:PolicyId = '11111111-1111-1111-1111-111111111111'

    function New-RemovedItem {
        param($OwnerId = 'gone/1', $Reason = 'Removed')
        [pscustomobject]@{ FunctionName = 'CloudBackupOwnerRemoved'; PolicyId = $script:PolicyId; customerId = 'c1'; Workload = 'exchange'; OwnerId = $OwnerId; OwnerType = 'UserMailbox'; DisplayName = 'Gone'; Reason = $Reason }
    }
    function Set-OwnerItems {
        param([int]$Count)
        $script:Items = [System.Collections.Generic.List[object]]::new()
        for ($i = 0; $i -lt $Count; $i++) {
            $script:Items.Add([pscustomobject]@{ Key = "items/inbox/m$i.fts"; Path = 'Inbox'; Name = "Mail $i"; Type = 'message'; Size = 5; Modified = '2026-11-01T00:00:00Z'; VersionId = "v$i"; Deleted = $false; Extra = [pscustomobject]@{ id = "id$i" }; RunStamp = '20261101T000000Z' })
        }
    }
    function Read-IndexPart {
        param([byte[]]$Bytes)
        $Gzip = [System.IO.Compression.GZipStream]::new([System.IO.MemoryStream]::new($Bytes), [System.IO.Compression.CompressionMode]::Decompress)
        $Reader = [System.IO.StreamReader]::new($Gzip)
        try { @(foreach ($Line in $Reader.ReadToEnd().Split("`n")) { if ($Line) { ConvertFrom-Json -InputObject $Line } }) } finally { $Reader.Dispose() }
    }
}

Describe 'Push-CloudBackupOwnerRemoved' {
    BeforeEach {
        $script:PolicyRow = New-CloudBackupPolicyRow -RetentionDays 30
        $script:StateRow = [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_gone_1'; Removed = $false }
        $script:StateWrites = [System.Collections.Generic.List[object]]::new()
        $script:Parts = [System.Collections.Generic.List[object]]::new()
        $script:Removed = [System.Collections.Generic.List[string]]::new()
        $script:DeletedAt = @{}
        Set-OwnerItems -Count 3
        Mock Get-CIPPAzDataTableEntity { $script:PolicyRow } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity { $script:StateRow } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Add-CIPPAzDataTableEntity { $script:StateWrites.Add([pscustomobject]@{ Entity = @{} + $Entity; OperationType = $OperationType }) } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Id = $Id; Provider = 'AzureBlob'; Secret = 's' } }
        Mock Get-CIPPCloudBackupKey { , [byte[]]::new(32) }
        Mock Get-CIPPCloudBackupOwnerListing {
            $Visible = @(foreach ($Entry in $script:Items) {
                    $Stamp = $script:DeletedAt[$Entry.Key]
                    if ($Stamp -and [datetime]::ParseExact($Stamp, 'yyyyMMddTHHmmssZ', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal) -le $AsOf) { continue }
                    $Entry
                })
            [pscustomobject]@{ RunStamp = '20261101T000000Z'; Total = $Visible.Count; Items = @($Visible | Select-Object -Skip $Skip -First $Take); Folders = @() }
        }
        Mock Remove-CIPPCloudBackupItem { $script:Removed.Add("$($Context.OwnerPrefix)$ItemKey") }
        Mock Write-CIPPCloudBackupItem {
            $Copy = [System.IO.MemoryStream]::new()
            $Stream.CopyTo($Copy)
            $Entries = Read-IndexPart -Bytes $Copy.ToArray()
            $script:Parts.Add([pscustomobject]@{ Key = $ItemKey; Entries = $Entries; Prefix = $Context.OwnerPrefix; KeyId = $Context.KeyId; ContentType = $ContentType })
            $Stamp = ($ItemKey -split '[/-]')[1]
            foreach ($Entry in $Entries) { $script:DeletedAt[$Entry.k] = $Stamp }
            [pscustomobject]@{ Key = $ItemKey; Bytes = $Copy.Length; VersionId = 'iv' }
        }
        Mock Write-LogMessage { }
    }

    It 'deletes every current item, writes the deletions as an index part and marks the owner removed' {
        $script:Items[1].Extra = [pscustomobject]@{ id = 'id1'; eml = 'items/inbox/m1.eml' }
        $script:Items.Add([pscustomobject]@{ Key = 'folders/f1/'; Path = 'Inbox'; Name = 'Inbox'; Type = 'folder'; Extra = [pscustomobject]@{ id = 'f1' } })
        $script:Items.Add([pscustomobject]@{ Key = 'items/c1/m9.json'; Path = 'Chat'; Name = 'Bob: hi'; Type = 'chatMessage'; Extra = [pscustomobject]@{ hostedContents = @('items/c1/m9/h1', 'items/c1/m9/h2') } })

        Push-CloudBackupOwnerRemoved -Item (New-RemovedItem)

        $Prefix = "$($script:PolicyId)/c1/exchange/gone_1/"
        @($script:Removed) | Should -Be @(
            "$($Prefix)items/inbox/m0.fts", "$($Prefix)items/inbox/m1.fts", "$($Prefix)items/inbox/m1.eml", "$($Prefix)items/inbox/m2.fts"
            "$($Prefix)items/c1/m9.json", "$($Prefix)items/c1/m9/h1", "$($Prefix)items/c1/m9/h2"
        )
        $script:Parts.Count | Should -Be 1
        $script:Parts[0].Prefix | Should -Be $Prefix
        $script:Parts[0].Key | Should -Match '^index/\d{8}T\d{6}Z-00000\.jsonl\.gz$'
        $script:Parts[0].ContentType | Should -Be 'application/gzip'
        $Entries = @($script:Parts[0].Entries)
        $Entries.Count | Should -Be 5
        foreach ($Entry in $Entries) { $Entry.d | Should -BeTrue; $Entry.v | Should -BeNullOrEmpty }
        $Entries[0].k | Should -Be 'items/inbox/m0.fts'
        $Entries[0].p | Should -Be 'Inbox'
        $Entries[0].t | Should -Be 'message'
        $Entries[0].x.id | Should -Be 'id0'
        $Entries[3].t | Should -Be 'folder'

        $script:StateWrites[0].Entity.State | Should -Be ''
        $Mark = $script:StateWrites[-1]
        $Mark.OperationType | Should -Be 'UpsertMerge'
        $Mark.Entity.PartitionKey | Should -Be "$($script:PolicyId)_c1"
        $Mark.Entity.RowKey | Should -Be 'exchange_gone_1'
        $Mark.Entity.Removed | Should -BeTrue
        $Mark.Entity.RemovedReason | Should -Be 'Removed'
        ([datetimeoffset]::Parse($Mark.Entity.RemovedAt).UtcDateTime - [datetime]::UtcNow).Duration().TotalMinutes | Should -BeLessThan 1
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Info' -and $message -like '*no longer in the tenant*30 days*' }
    }

    It 'records Excluded as the reason for an owner excluded from the policy' {
        Push-CloudBackupOwnerRemoved -Item (New-RemovedItem -Reason 'Excluded')
        $script:StateWrites[-1].Entity.RemovedReason | Should -Be 'Excluded'
    }

    It 'encrypts the index parts with the policy key when the policy encrypts' {
        $script:PolicyRow = New-CloudBackupPolicyRow -Encryption $true -CurrentKeyId 'k1'
        Mock Write-CIPPCloudBackupItem { $script:Parts.Add([pscustomobject]@{ Key = $ItemKey; KeyId = $Context.KeyId; Key2 = $Context.Key }) }

        Push-CloudBackupOwnerRemoved -Item (New-RemovedItem)

        $script:Parts[0].Key | Should -Match '\.jsonl\.gz\.enc$'
        $script:Parts[0].KeyId | Should -Be 'k1'
        $script:Parts[0].Key2.Length | Should -Be 32
    }

    It 'pages through the listing at a fixed point in time and writes one index part per page' {
        Set-OwnerItems -Count 2500

        Push-CloudBackupOwnerRemoved -Item (New-RemovedItem)

        $script:Removed.Count | Should -Be 2500
        @($script:Parts.Key | ForEach-Object { $_.Substring($_.Length - 14) }) | Should -Be @('00000.jsonl.gz', '00001.jsonl.gz', '00002.jsonl.gz')
        @($script:Parts | ForEach-Object { $_.Entries.Count }) | Should -Be @(1000, 1000, 500)
        @(@($script:Parts.Entries.k) | Sort-Object -Unique).Count | Should -Be 2500
        Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 3 -Exactly -ParameterFilter { $AsOf -is [datetime] -and $Take -eq 1000 -and $IncludeFolders -and -not $IncludeDeleted }
        $script:StateWrites[-1].Entity.Removed | Should -BeTrue
    }

    It 'stops after 5000 items without marking the owner, and a later run finishes the rest' {
        Set-OwnerItems -Count 6200

        Push-CloudBackupOwnerRemoved -Item (New-RemovedItem)

        $script:Removed.Count | Should -Be 5000
        @($script:StateWrites.Where({ $_.Entity.Removed })).Count | Should -Be 0

        foreach ($Key in @($script:DeletedAt.Keys)) { $script:DeletedAt[$Key] = '20260101T000000Z' }
        $script:Removed.Clear()
        Push-CloudBackupOwnerRemoved -Item (New-RemovedItem)

        $script:Removed.Count | Should -Be 1200
        $script:Removed[0] | Should -BeLike '*/items/inbox/m5000.fts'
        $script:StateWrites[-1].Entity.Removed | Should -BeTrue
    }

    It 'keeps going past an item that cannot be deleted, leaves it out of the index and does not mark the owner' {
        Mock Remove-CIPPCloudBackupItem { if ($ItemKey -like '*m1.fts') { throw 'blob locked' }; $script:Removed.Add($ItemKey) }

        Push-CloudBackupOwnerRemoved -Item (New-RemovedItem)

        @($script:Removed) | Should -Be @('items/inbox/m0.fts', 'items/inbox/m2.fts')
        @($script:Parts[0].Entries.k) | Should -Be @('items/inbox/m0.fts', 'items/inbox/m2.fts')
        @($script:StateWrites.Where({ $_.Entity.Removed })).Count | Should -Be 0
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*1 items could not*blob locked*' }
    }

    It 'marks an owner with nothing left as removed without writing an index part' {
        Set-OwnerItems -Count 0
        Push-CloudBackupOwnerRemoved -Item (New-RemovedItem)
        $script:Parts.Count | Should -Be 0
        $script:StateWrites[-1].Entity.Removed | Should -BeTrue
    }

    It 'does nothing for <Case>' -ForEach @(
        @{ Case = 'an owner already marked removed'; Setup = { $script:StateRow.Removed = $true } }
        @{ Case = 'an owner without a state row'; Setup = { $script:StateRow = $null } }
        @{ Case = 'a deleted policy'; Setup = { $script:PolicyRow = $null } }
    ) {
        & $Setup
        Push-CloudBackupOwnerRemoved -Item (New-RemovedItem)
        Should -Invoke Get-CIPPCloudBackupOwnerListing -Times 0 -Exactly
        $script:StateWrites.Count | Should -Be 0
    }

    It 'logs an error without throwing when the listing fails' {
        Mock Get-CIPPCloudBackupOwnerListing { throw 'storage down' }
        { Push-CloudBackupOwnerRemoved -Item (New-RemovedItem) } | Should -Not -Throw
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $message -like '*storage down*' }
        @($script:StateWrites.Where({ $_.Entity.Removed })).Count | Should -Be 0
    }
}

Describe 'Push-CloudBackupIndexMaintenance' {
    BeforeEach {
        $script:PolicyRow = New-CloudBackupPolicyRow -RetentionDays 30
        $script:StateRow = [pscustomobject]@{ PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'onedrive_u_2'; Status = 'Idle' }
        Mock Get-CIPPAzDataTableEntity { $script:PolicyRow } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity { $script:StateRow } -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Id = $Id; Provider = 'S3'; Secret = 's' } }
        Mock Get-CIPPCloudBackupKey { , [byte[]]::new(32) }
        Mock Invoke-CIPPCloudBackupIndexCompaction { [pscustomobject]@{ Compacted = $true; SnapshotStamp = '20261120T000000Z'; PartsMerged = 60 } }
        Mock Remove-CIPPCloudBackupIndexHistory { }
        Mock Write-LogMessage { }
        $script:Item = [pscustomobject]@{ FunctionName = 'CloudBackupIndexMaintenance'; PolicyId = $script:PolicyId; customerId = 'c1'; Workload = 'onedrive'; OwnerKey = 'u_2' }
    }

    It 'compacts the owner index and removes history older than the retention plus a day' {
        Push-CloudBackupIndexMaintenance -Item $script:Item

        $Prefix = "$($script:PolicyId)/c1/onedrive/u_2/"
        Should -Invoke Invoke-CIPPCloudBackupIndexCompaction -Times 1 -Exactly -ParameterFilter { $OwnerPrefix -eq $Prefix -and $Destination.Secret -eq 's' -and $null -eq $Key -and ($DeletedBefore - [datetime]::UtcNow.AddDays(-30)).Duration().TotalMinutes -lt 1 }
        Should -Invoke Remove-CIPPCloudBackupIndexHistory -Times 1 -Exactly -ParameterFilter {
            $OwnerPrefix -eq $Prefix -and ($OlderThan - [datetime]::UtcNow.AddDays(-31)).Duration().TotalMinutes -lt 1
        }
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'CloudBackupState' -and $Filter -eq "PartitionKey eq '$($script:PolicyId)_c1' and RowKey eq 'onedrive_u_2'" -and ($Property -contains 'RowKey') }
    }

    It 'passes the policy key when the policy encrypts' {
        $script:PolicyRow = New-CloudBackupPolicyRow -Encryption $true -CurrentKeyId 'k1'
        Push-CloudBackupIndexMaintenance -Item $script:Item
        Should -Invoke Invoke-CIPPCloudBackupIndexCompaction -Times 1 -Exactly -ParameterFilter { $KeyId -eq 'k1' -and $Key.Length -eq 32 }
    }

    It 'skips <Case>' -ForEach @(
        @{ Case = 'an owner whose backup is running'; Setup = { $script:StateRow.Status = 'Running' } }
        @{ Case = 'an owner without a state row'; Setup = { $script:StateRow = $null } }
        @{ Case = 'a deleted policy'; Setup = { $script:PolicyRow = $null } }
    ) {
        & $Setup
        Push-CloudBackupIndexMaintenance -Item $script:Item
        Should -Invoke Invoke-CIPPCloudBackupIndexCompaction -Times 0 -Exactly
        Should -Invoke Remove-CIPPCloudBackupIndexHistory -Times 0 -Exactly
    }

    It 'refuses an owner key that would break the table filter or the storage prefix' {
        $script:Item.OwnerKey = "x' or 1 eq 1"
        Push-CloudBackupIndexMaintenance -Item $script:Item
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly -ParameterFilter { $TableName -eq 'CloudBackupState' }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' }
    }

    It 'warns without throwing when compaction fails' {
        Mock Invoke-CIPPCloudBackupIndexCompaction { throw 'storage down' }
        { Push-CloudBackupIndexMaintenance -Item $script:Item } | Should -Not -Throw
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' -and $message -like '*storage down*' }
        Should -Invoke Remove-CIPPCloudBackupIndexHistory -Times 0 -Exactly
    }
}
