# Pester tests for threshold rules: counting records per identity from a blob index without building them
# (CippJson.JsonRecordIndex.CountWhere / IndicesWhere), and the batch task's counts and claims in AuditLogFeedThresholds.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    function Get-CippTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force, $OperationType) }
    function Update-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, $OperationType, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Get-CIPPAuditLogContent { param($Queries, $Blobs, [switch]$ListOnly, $Prefilters, $MaxConcurrency) }
    function Get-CIPPAuditLogPrefilter { param($TenantFilter) }
    function Get-CIPPAuditLogRuleSet { param($TenantFilter) }
    function Test-CIPPAuditLogRules { param($TenantFilter, $Rows, [switch]$EvaluateOnly, [switch]$CallerSweepsCachePartition) }
    function Invoke-CippWebhookProcessing { param($TenantFilter, $Data, $CIPPURL, $AlertComment, $PendingAuditLogWrites) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Push-AuditLogFeedBlobsV3.ps1')

    $script:Fields = [string[]]@('Operation', 'ClientIP', 'UserId', 'CreationTime')
    # A blob's records: @( @(operation, user, 'HH:mm:ss') ... ) on 2026-10-24.
    function New-BlobJson([object[]]$Rows) {
        ConvertTo-Json -Compress -Depth 4 -InputObject @(foreach ($R in $Rows) { [ordered]@{ Operation = $R[0]; UserId = $R[1]; CreationTime = "2026-10-24T$($R[2])"; ObjectId = "https://t.sharepoint.com/f-$($R[2]).docx"; Workload = 'SharePoint'; RecordType = 6 } })
    }
    function New-Task([string[]]$RowKeys) {
        [pscustomobject]@{ Tenants = @([pscustomobject]@{ TenantFilter = 'a.com'; TenantId = 'id-a'; Blobs = @(foreach ($Key in $RowKeys) { [pscustomobject]@{ RowKey = $Key; ContentType = 'Audit.SharePoint'; contentUri = "u-$Key" } }) }) }
    }
}

Describe 'JsonRecordIndex.CountWhere and IndicesWhere' {
    It 'counts the records of the given operations per identity and 10-minute bucket, ignoring case, without building them' {
        $Json = New-BlobJson @(
            @('FileRecycled', 'a@x', '17:01:00'), @('FileRecycled', 'a@x', '17:09:59'), @('filerecycled', 'a@x', '17:10:00')
            @('FileAccessed', 'a@x', '17:02:00'), @('FileDeletedSecondStageRecycleBin', 'b@x', '17:03:00')
        )
        $Index = [CIPP.CippJson]::IndexRecords($Json, $script:Fields)
        $Ops = [string[]]@('FileRecycled', 'FileDeletedSecondStageRecycleBin')
        $Counts = $Index.CountWhere(0, $Ops, [int[]]@(2, 3), [int[]]@(-1, 15))
        $Counts.Count | Should -Be 3
        $Counts['a@x|2026-10-24T17:0'] | Should -Be 2
        $Counts['A@X|2026-10-24T17:1'] | Should -Be 1
        $Counts['b@x|2026-10-24T17:0'] | Should -Be 1
        $Index.IndicesWhere(0, $Ops, [int[]]@(2, 3), [int[]]@(-1, 15), 'a@x|2026-10-24T17:0', 5) | Should -Be @(0, 1)
        $Index.IndicesWhere(0, $Ops, [int[]]@(2, 3), [int[]]@(-1, 15), 'a@x|2026-10-24T17:0', 1) | Should -Be @(0)
    }
}

Describe 'Push-AuditLogFeedBlobsV3 threshold rules' {
    BeforeEach {
        $script:Sent = [System.Collections.Generic.List[object]]::new()
        $script:Ops = [string[]]@('FileRecycled', 'FileDeletedSecondStageRecycleBin')
        $script:Rule = [pscustomobject]@{ RowKey = 'rule-1'; Actions = '[{"value":"generatePSA"}]'; AlertComment = 'Mass deletion'; CustomSubject = ''; PsaTicketPriority = ''; BecActions = '[]' }
        # AuditLogFeedThresholds in memory: an insert fails on an existing row, an update on a stale ETag.
        $script:Store = @{}
        $script:HideClaimOnce = $false
        Mock Get-CIPPAuditLogPrefilter { [pscustomobject]@{ Thresholds = @([pscustomobject]@{ Rule = $script:Rule; Operations = $script:Ops; Count = 5; Minutes = 20 }) } }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ Value = 'cipp.example' } }
        Mock Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'AuditLogFeedThresholds' } {
            $Pk = [regex]::Match($Filter, "PartitionKey eq '([^']*)'").Groups[1].Value
            $Eq = [regex]::Match($Filter, "RowKey eq '([^']*)'")
            if ($Eq.Success) {
                if ($script:HideClaimOnce) { $script:HideClaimOnce = $false; return }
                $Row = $script:Store["$Pk`n$($Eq.Groups[1].Value)"]
                if ($Row) { [pscustomobject]$Row }
                return
            }
            $Ge = [regex]::Match($Filter, "RowKey ge '([^']*)'").Groups[1].Value
            $Lt = [regex]::Match($Filter, "RowKey lt '([^']*)'").Groups[1].Value
            $From = [regex]::Match($Filter, "Bucket ge '([^']*)'").Groups[1].Value
            foreach ($Row in $script:Store.Values) {
                if ($Row.PartitionKey -eq $Pk -and [string]::CompareOrdinal($Row.RowKey, $Ge) -ge 0 -and [string]::CompareOrdinal($Row.RowKey, $Lt) -lt 0 -and [string]::CompareOrdinal($Row.Bucket, $From) -ge 0) { [pscustomobject]$Row }
            }
        }
        $script:RelatedRows = [System.Collections.Generic.List[object]]::new()
        Mock Add-CIPPAzDataTableEntity {}
        Mock Add-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'AuditLogRelatedRecords' } { $script:RelatedRows.Add($Entity) }
        Mock Add-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'AuditLogFeedThresholds' } {
            foreach ($Row in @($Entity)) {
                $Key = "$($Row.PartitionKey)`n$($Row.RowKey)"
                if (-not $Force -and $script:Store.ContainsKey($Key)) { throw 'The specified entity already exists.' }
                $Copy = @{} + $Row
                $Copy.ETag = [guid]::NewGuid().ToString()
                $script:Store[$Key] = $Copy
            }
        }
        Mock Update-CIPPAzDataTableEntity {
            $Key = "$($Entity.PartitionKey)`n$($Entity.RowKey)"
            if (-not $script:Store.ContainsKey($Key) -or $script:Store[$Key].ETag -ne $Entity.ETag) { throw 'The update condition specified in the request was not satisfied.' }
            $Copy = @{} + $Entity
            $Copy.ETag = [guid]::NewGuid().ToString()
            $script:Store[$Key] = $Copy
        }
        Mock Remove-CIPPAzDataTableEntity {}
        # As the real one does, a sent alert hands back its AuditLogs row to write.
        Mock Invoke-CippWebhookProcessing { $script:Sent.Add($Data); $PendingAuditLogWrites.Add(@{ PartitionKey = $TenantFilter; RowKey = $Data.Id }) }
        # Each blob as Get-CIPPAuditLogContent hands it over, with the counts it takes from the blob's index.
        Mock Get-CIPPAuditLogContent {
            foreach ($Blob in $Blobs) {
                $Index = [CIPP.CippJson]::IndexRecords($script:BlobJson[$Blob.RowKey], $script:Fields)
                $Counts = $Index.CountWhere(0, $script:Ops, [int[]]@(2, 3), [int[]]@(-1, 15))
                [pscustomobject]@{ Kind = 'Blob'; TenantId = $Blob.TenantId; Blob = $Blob; RecordCount = $Index.Count; Records = @(); ParseMs = 0; Error = $null; TenantDone = $false; Skipped = $false
                    Counts = @(if ($Counts.Count) { [pscustomobject]@{ Threshold = 0; Counts = $Counts; Index = $Index } })
                }
            }
        }
        $script:BlobJson = @{
            r1 = New-BlobJson @(@('FileRecycled', 'bob@a.com', '17:01:00'), @('FileRecycled', 'bob@a.com', '17:02:00'), @('FileAccessed', 'bob@a.com', '17:03:00'), @('FileRecycled', 'eve@a.com', '17:04:00'))
            r2 = New-BlobJson @(@('FileDeletedSecondStageRecycleBin', 'bob@a.com', '17:12:00'), @('FileRecycled', 'Bob@a.com', '17:13:00'), @('FileRecycled', 'bob@a.com', '17:14:00'))
            r3 = New-BlobJson @(@('FileRecycled', 'bob@a.com', '17:45:00'), @('FileRecycled', 'bob@a.com', '17:46:00'), @('FileRecycled', 'eve@a.com', '17:47:00'))
        }
    }

    It 'alerts once when one identity''s deletions across the batch''s blobs reach the count within the window' {
        Push-AuditLogFeedBlobsV3 -Item (New-Task 'r1', 'r2')
        $script:Sent | Should -HaveCount 1
        $Alert = $script:Sent[0]
        $Alert.UserId | Should -Be 'bob@a.com'
        $Alert.CIPPThresholdCount | Should -Be 5
        $Alert.Id | Should -Be 'threshold-rule-1-bob@a.com-202610241720'
        $Alert.CIPPClause | Should -BeLike '5 of FileRecycled, FileDeletedSecondStageRecycleBin by bob@a.com within 20 minutes*'
        $Alert.CIPPAction | Should -Be $script:Rule.Actions
        @([CIPP.CippJson]::ConvertFromJson($Alert.AuditRecord)).Count | Should -BeGreaterThan 0
        # Every record of the burst is kept beside the alert, in time order, not only the samples.
        $script:RelatedRows | Should -HaveCount 1
        $script:RelatedRows[0].RowKey | Should -Be $Alert.Id
        $Kept = @([CIPP.CippJson]::ConvertFromJson($script:RelatedRows[0].Records))
        $Kept | Should -HaveCount 5
        @($Kept.Time | ForEach-Object { if ($_ -is [datetime]) { $_.ToString('yyyy-MM-ddTHH:mm:ss') } else { $_ } }) | Should -Be @('2026-10-24T17:01:00', '2026-10-24T17:02:00', '2026-10-24T17:12:00', '2026-10-24T17:13:00', '2026-10-24T17:14:00')
        $Kept[0].Item | Should -BeLike '*f-17:01:00.docx'
        $Kept.Operation | Should -Contain 'FileDeletedSecondStageRecycleBin'
    }

    It 'keeps the related records of an identity whose name has characters a row key cannot hold' {
        $Who = 'contoso.onmicrosoft.com\tenant: 1, object: 2'
        $script:BlobJson = @{ r1 = New-BlobJson @(foreach ($Minute in 1..5) { , @('FileRecycled', $Who, ('17:0{0}:00' -f $Minute)) }) }
        Push-AuditLogFeedBlobsV3 -Item (New-Task 'r1')
        $script:Sent | Should -HaveCount 1
        $script:RelatedRows | Should -HaveCount 1
        @([CIPP.CippJson]::ConvertFromJson($script:RelatedRows[0].Records)) | Should -HaveCount 5
    }

    It 'sums an identity''s counts across runs, alerts the run that reaches the count, and never again for that burst' {
        Push-AuditLogFeedBlobsV3 -Item (New-Task 'r1')
        $script:Sent | Should -HaveCount 0
        Push-AuditLogFeedBlobsV3 -Item (New-Task 'r2')
        $script:Sent | Should -HaveCount 1
        $script:Sent[0].CIPPThresholdCount | Should -Be 5
        Push-AuditLogFeedBlobsV3 -Item (New-Task 'r1', 'r2')
        $script:Sent | Should -HaveCount 1
    }

    It 'counts a blob evaluated twice once' {
        Push-AuditLogFeedBlobsV3 -Item (New-Task 'r1')
        Push-AuditLogFeedBlobsV3 -Item (New-Task 'r1')
        Push-AuditLogFeedBlobsV3 -Item (New-Task 'r3')
        $script:Sent | Should -HaveCount 0
    }

    It 'does not alert when another task claimed the burst between its read and its write' {
        Push-AuditLogFeedBlobsV3 -Item (New-Task 'r1', 'r2')
        $script:Sent | Should -HaveCount 1
        # The second task reads no claim yet, so its insert fails; it reads again and finds the burst covered.
        $script:HideClaimOnce = $true
        Push-AuditLogFeedBlobsV3 -Item (New-Task 'r2')
        $script:Sent | Should -HaveCount 1
        Should -Invoke Add-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'AuditLogFeedThresholds' -and -not $Force } -Times 2 -Exactly
    }

    It 'does not alert below the count, or when the records are further apart than the window' {
        Push-AuditLogFeedBlobsV3 -Item (New-Task 'r1', 'r3')
        $script:Sent | Should -HaveCount 0
    }
}
