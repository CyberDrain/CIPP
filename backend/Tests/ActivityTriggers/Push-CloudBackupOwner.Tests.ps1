BeforeAll {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'Fixtures/CloudBackup/CloudBackupTestStubs.ps1')
    $script:PolicyId = '11111111-1111-1111-1111-111111111111'

    function New-OwnerItem {
        param($RunId = "$($script:PolicyId)_0000000000000000001_c1_exchange", $RunStamp = '20261120T000000Z', $Workload = 'exchange', $OwnerId = 'u1', $OwnerType = 'UserMailbox')
        [pscustomobject]@{
            FunctionName      = 'CloudBackupOwner'
            PolicyId          = $script:PolicyId
            customerId        = 'c1'
            Workload          = $Workload
            OwnerId           = $OwnerId
            OwnerType         = $OwnerType
            DisplayName       = 'Ann'
            UserId            = $OwnerId
            UserPrincipalName = 'ann@contoso.com'
            SiteUrl           = $null
            RunId             = $RunId
            RunStamp          = $RunStamp
        }
    }

    function Get-StoredRow {
        param($Table, $PartitionKey, $RowKey)
        $script:Store["$Table|$PartitionKey|$RowKey"]
    }

    function ConvertFrom-GzipBytes {
        param([byte[]]$Bytes)
        $Source = [System.IO.MemoryStream]::new($Bytes)
        $Gzip = [System.IO.Compression.GZipStream]::new($Source, [System.IO.Compression.CompressionMode]::Decompress)
        $Reader = [System.IO.StreamReader]::new($Gzip)
        try { $Reader.ReadToEnd() } finally { $Reader.Dispose() }
    }
}

Describe 'Push-CloudBackupOwner' {
    BeforeEach {
        $script:Store = @{}
        $script:Log = [System.Collections.Generic.List[string]]::new()
        $script:Uploads = [System.Collections.Generic.List[object]]::new()
        $script:StateWrites = 0
        $script:StepStates = [System.Collections.Generic.List[object]]::new()
        $script:Contexts = [System.Collections.Generic.List[object]]::new()
        $script:CrashAt = -1
        $script:LastPage = 4
        $script:PolicyRow = New-CloudBackupPolicyRow

        Mock Get-CIPPAzDataTableEntity { $script:PolicyRow } -ParameterFilter { $TableName -eq 'Config' }
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -match "PartitionKey eq '([^']*)' and RowKey eq '([^']*)'") {
                $Row = $script:Store["$TableName|$($Matches[1])|$($Matches[2])"]
                if ($Row) { [pscustomobject]$Row }
            }
        } -ParameterFilter { $TableName -in @('CloudBackupState', 'CloudBackupRunOwners') }
        Mock Add-CIPPAzDataTableEntity {
            foreach ($Row in @($Entity)) {
                $script:Store["$TableName|$($Row.PartitionKey)|$($Row.RowKey)"] = @{} + $Row
                if ($TableName -eq 'CloudBackupState') { $script:StateWrites++; $script:Log.Add("state:$($Row.Status)") }
            }
        } -ParameterFilter { $TableName -in @('CloudBackupState', 'CloudBackupRunOwners') }
        Mock Get-Tenants { $script:CloudBackupTenants[0] }
        Mock Get-CIPPCloudBackupDestination { [pscustomobject]@{ Id = '22222222-2222-2222-2222-222222222222'; Name = 'Blob'; Provider = 'AzureBlob' } }
        Mock Get-CIPPCloudBackupKey { , [byte[]]::new(32) }
        Mock Send-CIPPCloudBackupObjectStream {
            $Copy = [System.IO.MemoryStream]::new()
            $Stream.CopyTo($Copy)
            $script:Uploads.Add([pscustomobject]@{ Key = $Key; Bytes = $Copy.ToArray(); ContentType = $ContentType; KeyId = $KeyId; EncryptionKey = $EncryptionKey })
            $script:Log.Add("upload:$Key")
            [pscustomobject]@{ Key = $Key; Bytes = $Copy.Length; VersionId = "v$($script:Uploads.Count)" }
        }
        Mock Write-LogMessage { }
        Mock Invoke-CIPPCloudBackupExchangeStep {
            $script:StepStates.Add($State)
            $script:Contexts.Add($Context)
            $Page = if ($State) { [int]$State.Page } else { 0 }
            if ($Page -eq $script:CrashAt) { throw 'worker stopped' }
            $Written = Write-CIPPCloudBackupItem -Context $Context -ItemKey "items/inbox/$Page.fts" -Body ([byte[]](1, 2, 3))
            [pscustomobject]@{
                State        = [ordered]@{ Page = $Page + 1; Token = "AbC$Page" }
                Done         = ($Page + 1) -ge $script:LastPage
                Items        = 1
                Bytes        = 3
                Deleted      = 0
                Warnings     = @()
                IndexEntries = @([pscustomobject]@{ k = "items/inbox/$Page.fts"; p = 'Inbox'; n = "Mail $Page"; t = 'message'; s = 3; m = '2026-11-20T00:00:00Z'; v = $Written.VersionId; d = $false; x = @{ from = 'a@b.c' } })
            }
        }
    }

    It 'runs the steps until Done, writing each step''s items, then its index part, then its state' {
        Push-CloudBackupOwner -Item (New-OwnerItem)

        Should -Invoke Invoke-CIPPCloudBackupExchangeStep -Times 4 -Exactly
        $Prefix = "$($script:PolicyId)/c1/exchange/u1/"
        @($script:Log) | Should -Be @(
            "upload:$($Prefix)items/inbox/0.fts", "upload:$($Prefix)index/20261120T000000Z-00000.jsonl.gz", 'state:Running'
            "upload:$($Prefix)items/inbox/1.fts", "upload:$($Prefix)index/20261120T000000Z-00001.jsonl.gz", 'state:Running'
            "upload:$($Prefix)items/inbox/2.fts", "upload:$($Prefix)index/20261120T000000Z-00002.jsonl.gz", 'state:Running'
            "upload:$($Prefix)items/inbox/3.fts", "upload:$($Prefix)index/20261120T000000Z-00003.jsonl.gz", 'state:Idle'
        )
        $State = Get-StoredRow -Table 'CloudBackupState' -PartitionKey "$($script:PolicyId)_c1" -RowKey 'exchange_u1'
        $State.Status | Should -Be 'Idle'
        $State.State | Should -Be '{"Page":4,"Token":"AbC3"}'
        $State.Items | Should -Be 4
        $State.Bytes | Should -Be 12
        $State.OwnerType | Should -Be 'UserMailbox'
        $State.LastSuccessAt | Should -Not -BeNullOrEmpty
        $Result = Get-StoredRow -Table 'CloudBackupRunOwners' -PartitionKey "$($script:PolicyId)_0000000000000000001_c1_exchange" -RowKey 'u1'
        $Result.Status | Should -Be 'Succeeded'
        $Result.Items | Should -Be 4
        $Result.Bytes | Should -Be 12
        $Result.Steps | Should -Be 4
        $Result.UserPrincipalName | Should -Be 'ann@contoso.com'
        $Result.CompletedAt | Should -Not -BeNullOrEmpty
    }

    It 'gives the step the documented context and the previous step''s state' {
        Push-CloudBackupOwner -Item (New-OwnerItem)

        $Context = $script:Contexts[0]
        $Context.TenantFilter | Should -Be 'contoso.com'
        $Context.TenantId | Should -Be 'c1'
        $Context.PolicyId | Should -Be $script:PolicyId
        $Context.Workload | Should -Be 'exchange'
        $Context.OwnerId | Should -Be 'u1'
        $Context.OwnerType | Should -Be 'UserMailbox'
        $Context.Owner.UserPrincipalName | Should -Be 'ann@contoso.com'
        $Context.RunId | Should -Be "$($script:PolicyId)_0000000000000000001_c1_exchange"
        $Context.RunStamp | Should -Be '20261120T000000Z'
        $Context.OwnerPrefix | Should -Be "$($script:PolicyId)/c1/exchange/u1/"
        $Context.Destination.Name | Should -Be 'Blob'
        $Context.Key | Should -BeNullOrEmpty
        $script:StepStates[0] | Should -BeNullOrEmpty
        $script:StepStates[1].Page | Should -Be 1
        $script:StepStates[1].Token | Should -BeExactly 'AbC0'
    }

    It 'writes each index part as gzip JSON lines in the storage layout' {
        Push-CloudBackupOwner -Item (New-OwnerItem)

        $Index = $script:Uploads.Where({ $_.Key -like '*index/*-00002.jsonl.gz' })[0]
        $Index.ContentType | Should -Be 'application/gzip'
        $Lines = @((ConvertFrom-GzipBytes -Bytes $Index.Bytes).Split("`n").Where({ $_ }))
        $Lines.Count | Should -Be 1
        $Entry = $Lines[0] | ConvertFrom-Json
        $Entry.k | Should -Be 'items/inbox/2.fts'
        $Entry.n | Should -Be 'Mail 2'
        $Entry.t | Should -Be 'message'
        $Entry.v | Should -Be 'v5'
        $Entry.x.from | Should -Be 'a@b.c'
    }

    It 'encrypts items and index parts with the policy key and names the index .enc' {
        $script:PolicyRow = New-CloudBackupPolicyRow -Encryption $true -CurrentKeyId 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' -KeyIds '["aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"]'
        $script:LastPage = 1

        Push-CloudBackupOwner -Item (New-OwnerItem)

        @($script:Uploads.Key) | Should -Be @("$($script:PolicyId)/c1/exchange/u1/items/inbox/0.fts", "$($script:PolicyId)/c1/exchange/u1/index/20261120T000000Z-00000.jsonl.gz.enc")
        foreach ($Upload in $script:Uploads) {
            $Upload.KeyId | Should -Be 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            $Upload.EncryptionKey.Length | Should -Be 32
        }
        Should -Invoke Get-CIPPCloudBackupKey -Times 1 -Exactly -ParameterFilter { $KeyId -eq 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' }
    }

    It 'resumes after a crash mid-owner from the saved state without re-writing finished items' {
        $script:CrashAt = 2
        Push-CloudBackupOwner -Item (New-OwnerItem)

        $FirstRun = Get-StoredRow -Table 'CloudBackupRunOwners' -PartitionKey "$($script:PolicyId)_0000000000000000001_c1_exchange" -RowKey 'u1'
        $FirstRun.Status | Should -Be 'Failed'
        $FirstRun.Error | Should -Be 'worker stopped'
        $FirstRun.Items | Should -Be 2
        $Saved = Get-StoredRow -Table 'CloudBackupState' -PartitionKey "$($script:PolicyId)_c1" -RowKey 'exchange_u1'
        $Saved.Status | Should -Be 'Error'
        $Saved.LastError | Should -Be 'worker stopped'
        $Saved.State | Should -Be '{"Page":2,"Token":"AbC1"}'
        $FirstUploads = @($script:Uploads.Key.Where({ $_ -like '*/items/*' }))
        $FirstUploads | Should -Be @("$($script:PolicyId)/c1/exchange/u1/items/inbox/0.fts", "$($script:PolicyId)/c1/exchange/u1/items/inbox/1.fts")

        $script:CrashAt = -1
        $script:Uploads.Clear()
        $script:StepStates.Clear()
        Push-CloudBackupOwner -Item (New-OwnerItem -RunId "$($script:PolicyId)_0000000000000000002_c1_exchange" -RunStamp '20261120T040000Z')

        $script:StepStates[0].Page | Should -Be 2
        $script:StepStates[0].Token | Should -BeExactly 'AbC1'
        @($script:Uploads.Key.Where({ $_ -like '*/items/*' })) | Should -Be @("$($script:PolicyId)/c1/exchange/u1/items/inbox/2.fts", "$($script:PolicyId)/c1/exchange/u1/items/inbox/3.fts")
        @($script:Uploads.Key.Where({ $_ -like '*/index/*' })) | Should -Be @("$($script:PolicyId)/c1/exchange/u1/index/20261120T040000Z-00000.jsonl.gz", "$($script:PolicyId)/c1/exchange/u1/index/20261120T040000Z-00001.jsonl.gz")
        $State = Get-StoredRow -Table 'CloudBackupState' -PartitionKey "$($script:PolicyId)_c1" -RowKey 'exchange_u1'
        $State.Status | Should -Be 'Idle'
        $State.Items | Should -Be 4
        $State.LastError | Should -Be ''
        (Get-StoredRow -Table 'CloudBackupRunOwners' -PartitionKey "$($script:PolicyId)_0000000000000000002_c1_exchange" -RowKey 'u1').Status | Should -Be 'Succeeded'
    }

    It 'stores the owner details, keeps LastCompactedAt and backs up an owner that came back after being marked removed' {
        $script:Store["CloudBackupState|$($script:PolicyId)_c1|exchange_u1"] = @{
            PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_u1'; OwnerId = 'u1'; OwnerType = 'UserMailbox'; State = ''; Status = 'Idle'
            LastCompactedAt = '2026-11-19T00:00:00.0000000Z'; Removed = $true; RemovedAt = '2026-11-18T00:00:00.0000000Z'; RemovedReason = 'Removed'
        }

        Push-CloudBackupOwner -Item (New-OwnerItem)

        $script:StepStates[0] | Should -BeNullOrEmpty
        $State = Get-StoredRow -Table 'CloudBackupState' -PartitionKey "$($script:PolicyId)_c1" -RowKey 'exchange_u1'
        $State.DisplayName | Should -Be 'Ann'
        $State.UserPrincipalName | Should -Be 'ann@contoso.com'
        $State.SiteUrl | Should -Be ''
        $State.LastCompactedAt | Should -Be '2026-11-19T00:00:00.0000000Z'
        $State.Removed | Should -BeFalse
        $State.RemovedAt | Should -Be ''
        $State.RemovedReason | Should -Be ''
    }

    It 'resumes a worker killed without recording anything, continuing the same run''s index part numbering' {
        $RunId = "$($script:PolicyId)_0000000000000000001_c1_exchange"
        $script:Store["CloudBackupState|$($script:PolicyId)_c1|exchange_u1"] = @{
            PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_u1'; OwnerId = 'u1'; OwnerType = 'UserMailbox'
            State = '{"Page":3,"Token":"AbC2"}'; Status = 'Running'; LastRunId = $RunId; Items = 3; Bytes = 9; IndexRunId = $RunId; IndexPart = 3
        }

        Push-CloudBackupOwner -Item (New-OwnerItem -RunId $RunId)

        Should -Invoke Invoke-CIPPCloudBackupExchangeStep -Times 1 -Exactly
        $script:StepStates[0].Page | Should -Be 3
        @($script:Uploads.Key) | Should -Be @("$($script:PolicyId)/c1/exchange/u1/items/inbox/3.fts", "$($script:PolicyId)/c1/exchange/u1/index/20261120T000000Z-00003.jsonl.gz")
        $State = Get-StoredRow -Table 'CloudBackupState' -PartitionKey "$($script:PolicyId)_c1" -RowKey 'exchange_u1'
        $State.Items | Should -Be 4
        $State.IndexPart | Should -Be 4
    }

    It 'keeps a large state intact between steps' {
        $Folders = [ordered]@{}
        foreach ($i in 1..2000) { $Folders["AAMkAD$($i)xYz=="] = "https://graph.microsoft.com/beta/admin/exchange/mailboxes/MBX:1/folders/f$i/items/delta?`$deltatoken=" + ('Qw' * 100) }
        $Big = @{ Page = 0; Folders = $Folders }
        $script:Store["CloudBackupState|$($script:PolicyId)_c1|exchange_u1"] = @{
            PartitionKey = "$($script:PolicyId)_c1"; RowKey = 'exchange_u1'; State = ([CIPP.CippJson]::ToJson($Big, 20) ?? ($Big | ConvertTo-Json -Depth 20 -Compress)); Status = 'Idle'
        }
        $script:StoredLength = $script:Store["CloudBackupState|$($script:PolicyId)_c1|exchange_u1"].State.Length
        Mock Invoke-CIPPCloudBackupExchangeStep {
            $script:StepStates.Add($State)
            [pscustomobject]@{ State = $State; Done = $true; Items = 0; Bytes = 0; Deleted = 0; Warnings = @(); IndexEntries = @() }
        }

        Push-CloudBackupOwner -Item (New-OwnerItem)

        $script:StoredLength | Should -BeGreaterThan 400000
        $script:StepStates[0].Folders.Count | Should -Be 2000
        $script:StepStates[0].Folders['AAMkAD1999xYz=='] | Should -BeLike '*deltatoken=QwQw*'
        $Saved = Get-StoredRow -Table 'CloudBackupState' -PartitionKey "$($script:PolicyId)_c1" -RowKey 'exchange_u1'
        $Saved.State.Length | Should -Be $script:StoredLength
        @($script:Uploads).Count | Should -Be 0
    }

    It 'records warnings as PartialSuccess, counting all and storing at most 50' {
        $script:LastPage = 1
        Mock Invoke-CIPPCloudBackupExchangeStep {
            [pscustomobject]@{ State = @{ Page = 1 }; Done = $true; Items = 5; Bytes = 10; Deleted = 2; Warnings = @(foreach ($i in 1..60) { "item $i failed" }); IndexEntries = @() }
        }

        Push-CloudBackupOwner -Item (New-OwnerItem)

        $Result = Get-StoredRow -Table 'CloudBackupRunOwners' -PartitionKey "$($script:PolicyId)_0000000000000000001_c1_exchange" -RowKey 'u1'
        $Result.Status | Should -Be 'PartialSuccess'
        $Result.WarningCount | Should -Be 60
        @($Result.Warnings | ConvertFrom-Json).Count | Should -Be 50
        $Result.Deleted | Should -Be 2
    }

    It 'records a failed owner without throwing when <Case>' -ForEach @(
        @{ Case = 'the policy is gone'; Setup = { $script:PolicyRow = $null } }
        @{ Case = 'the destination is gone'; Setup = { Mock Get-CIPPCloudBackupDestination { } } }
        @{ Case = 'the tenant is gone'; Setup = { Mock Get-Tenants { } } }
        @{ Case = 'the workload is unknown'; Setup = { $script:Workload = 'config' } }
    ) {
        $script:Workload = 'exchange'
        & $Setup

        { Push-CloudBackupOwner -Item (New-OwnerItem -Workload $script:Workload) } | Should -Not -Throw

        $Result = Get-StoredRow -Table 'CloudBackupRunOwners' -PartitionKey "$($script:PolicyId)_0000000000000000001_c1_exchange" -RowKey 'u1'
        $Result.Status | Should -Be 'Failed'
        $Result.Error | Should -Not -BeNullOrEmpty
        Should -Invoke Invoke-CIPPCloudBackupExchangeStep -Times 0 -Exactly
        Should -Invoke Write-LogMessage -ParameterFilter { $sev -eq 'Error' }
    }

    It 'keys SharePoint site ids with commas as they are and replaces characters table keys refuse' {
        Mock Invoke-CIPPCloudBackupSharePointStep {
            $script:Contexts.Add($Context)
            [pscustomobject]@{ State = @{ RunId = $Context.RunId }; Done = $true; Items = 0; Bytes = 0; Deleted = 0; Warnings = @(); IndexEntries = @() }
        }

        Push-CloudBackupOwner -Item (New-OwnerItem -Workload 'sharepoint' -OwnerId 'contoso.sharepoint.com,a1b2,c3d4' -OwnerType 'Site' -RunId "$($script:PolicyId)_0000000000000000001_c1_sharepoint")
        Push-CloudBackupOwner -Item (New-OwnerItem -Workload 'sharepoint' -OwnerId "odd/id#with?chars'" -OwnerType 'Site' -RunId "$($script:PolicyId)_0000000000000000001_c1_sharepoint")

        $script:Contexts[0].OwnerPrefix | Should -Be "$($script:PolicyId)/c1/sharepoint/contoso.sharepoint.com,a1b2,c3d4/"
        $script:Contexts[0].OwnerId | Should -Be 'contoso.sharepoint.com,a1b2,c3d4'
        (Get-StoredRow -Table 'CloudBackupState' -PartitionKey "$($script:PolicyId)_c1" -RowKey 'sharepoint_contoso.sharepoint.com,a1b2,c3d4').OwnerId | Should -Be 'contoso.sharepoint.com,a1b2,c3d4'
        $script:Contexts[1].OwnerPrefix | Should -Be "$($script:PolicyId)/c1/sharepoint/odd_id_with_chars_/"
        $script:Contexts[1].OwnerId | Should -Be "odd/id#with?chars'"
        $Row = Get-StoredRow -Table 'CloudBackupRunOwners' -PartitionKey "$($script:PolicyId)_0000000000000000001_c1_sharepoint" -RowKey 'odd_id_with_chars_'
        $Row.OwnerId | Should -Be "odd/id#with?chars'"
        $Row.Status | Should -Be 'Succeeded'
    }
}
