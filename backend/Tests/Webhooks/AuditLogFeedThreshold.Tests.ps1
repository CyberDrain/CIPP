# Pester tests for threshold rules: counting records per identity from a blob index without building them
# (CippJson.JsonRecordIndex.CountWhere / IndicesWhere), the prefilter's Thresholds, and the batch task's alert.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    function Get-CippTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force, $OperationType) }
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
        Mock Get-CIPPAuditLogPrefilter { [pscustomobject]@{ Thresholds = @([pscustomobject]@{ Rule = $script:Rule; Operations = $script:Ops; Count = 5; Minutes = 20 }) } }
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ Value = 'cipp.example' } }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Remove-CIPPAzDataTableEntity {}
        Mock Invoke-CippWebhookProcessing { $script:Sent.Add($Data) }
        # Each blob as Get-CIPPAuditLogContent hands it over, with the counts it takes from the blob's index.
        $script:BlobJson = @()
        Mock Get-CIPPAuditLogContent {
            $n = 0
            foreach ($Blob in $Blobs) {
                $Index = [CIPP.CippJson]::IndexRecords($script:BlobJson[$n++], $script:Fields)
                $Counts = $Index.CountWhere(0, $script:Ops, [int[]]@(2, 3), [int[]]@(-1, 15))
                [pscustomobject]@{ Kind = 'Blob'; TenantId = $Blob.TenantId; Blob = $Blob; RecordCount = $Index.Count; Records = @(); ParseMs = 0; Error = $null; TenantDone = $false; Skipped = $false
                    Counts = @(if ($Counts.Count) { [pscustomobject]@{ Threshold = 0; Counts = $Counts; Index = $Index } }) }
            }
        }
        $script:Item = [pscustomobject]@{ Tenants = @([pscustomobject]@{ TenantFilter = 'a.com'; TenantId = 'id-a'; Blobs = @([pscustomobject]@{ RowKey = 'r1'; ContentType = 'Audit.SharePoint'; contentUri = 'u1' }, [pscustomobject]@{ RowKey = 'r2'; ContentType = 'Audit.SharePoint'; contentUri = 'u2' }) }) }
    }

    It 'alerts once when one identity''s deletions across the batch''s blobs reach the count within the window' {
        $script:BlobJson = @(
            (New-BlobJson @(@('FileRecycled', 'bob@a.com', '17:01:00'), @('FileRecycled', 'bob@a.com', '17:02:00'), @('FileAccessed', 'bob@a.com', '17:03:00'), @('FileRecycled', 'eve@a.com', '17:04:00'))),
            (New-BlobJson @(@('FileDeletedSecondStageRecycleBin', 'bob@a.com', '17:12:00'), @('FileRecycled', 'bob@a.com', '17:13:00'), @('FileRecycled', 'bob@a.com', '17:14:00')))
        )
        Push-AuditLogFeedBlobsV3 -Item $script:Item
        $script:Sent | Should -HaveCount 1
        $Alert = $script:Sent[0]
        $Alert.UserId | Should -Be 'bob@a.com'
        $Alert.CIPPThresholdCount | Should -Be 5
        $Alert.Id | Should -Be 'threshold-rule-1-bob@a.com-2026102417'
        $Alert.CIPPClause | Should -BeLike '5 of FileRecycled, FileDeletedSecondStageRecycleBin by bob@a.com within 20 minutes*'
        $Alert.CIPPAction | Should -Be $script:Rule.Actions
        @([CIPP.CippJson]::ConvertFromJson($Alert.AuditRecord)).Count | Should -Be 2
        $Alert.ObjectId | Should -BeLike '*f-17:01:00.docx*'
    }

    It 'does not alert below the count, or when the records are further apart than the window' {
        $script:BlobJson = @(
            (New-BlobJson @(@('FileRecycled', 'bob@a.com', '17:01:00'), @('FileRecycled', 'bob@a.com', '17:02:00'), @('FileRecycled', 'bob@a.com', '17:03:00'))),
            (New-BlobJson @(@('FileRecycled', 'bob@a.com', '17:45:00'), @('FileRecycled', 'bob@a.com', '17:46:00'), @('FileRecycled', 'eve@a.com', '17:47:00')))
        )
        Push-AuditLogFeedBlobsV3 -Item $script:Item
        $script:Sent | Should -HaveCount 0
    }
}
