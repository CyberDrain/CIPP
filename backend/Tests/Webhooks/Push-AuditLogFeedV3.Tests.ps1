# Pester tests for Push-AuditLogFeedV3 - the Management Activity API feed stage.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')

    function Get-CippTable { param($TableName) @{ TableName = $TableName } }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force, $OperationType) }
    function Get-CIPPAuditLogContent { param($Queries, $Prefilters, $MaxConcurrency) }
    function Get-CIPPAuditLogPrefilter { param($TenantFilter) }
    function Get-CippAuditLogNextAttempt { param($Attempts) }
    function New-GraphPOSTRequest { param($type, $uri, $body, $scope, $tenantid, $NoAuthCheck) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Test-CIPPAuditLogRules { param($TenantFilter, $Rows, [switch]$EvaluateOnly) }

    function New-FeedItem {
        param([hashtable]$Cursors = @{}, [string[]]$ContentTypes = @('Audit.Exchange'))
        [pscustomobject]@{ Tenants = @([pscustomobject]@{ TenantFilter = 'contoso.com'; TenantId = 'tid-1'; ContentTypes = $ContentTypes; Cursors = $Cursors }) }
    }
    function New-Listing {
        param($Query, [object[]]$Blobs = @(), $ErrorCode, $ErrorMessage)
        [pscustomobject]@{
            Kind = 'Listing'; TenantDone = $false
            TenantFilter = $Query.TenantFilter; TenantId = $Query.TenantId; ContentType = $Query.ContentType
            StartTime = $Query.StartTime; EndTime = $Query.EndTime; Blobs = $Blobs; StatusCode = 200; ErrorCode = $ErrorCode; Error = $ErrorMessage
        }
    }
    function New-Blob([string]$TenantId, [string]$ContentType, [string]$Id = 'x') {
        [pscustomobject]@{ contentId = $Id; contentType = $ContentType; contentUri = "https://manage.office.com/api/v1.0/$TenantId/activity/feed/audit/$Id" }
    }
    function New-Download($Blob, [object[]]$Records = @(), $ErrorMessage, $ErrorCode) {
        [pscustomobject]@{ Kind = 'Blob'; TenantDone = $false; TenantId = ([uri]$Blob.contentUri).Segments[3].TrimEnd('/'); Blob = $Blob; RecordCount = $Records.Count; Records = $Records; Error = $ErrorMessage; ErrorCode = $ErrorCode }
    }
    function New-Record([string]$Id, [string]$Operation = 'New-InboxRule') {
        [pscustomobject]@{ Id = $Id; Operation = $Operation; RecordType = 1; CreationTime = '2026-10-17T05:00:00'; UserId = 'a@contoso.com' }
    }

    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Push-AuditLogFeedV3.ps1')
}

Describe 'Push-AuditLogFeedV3' {

    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Queries = $null
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add([pscustomobject]@{ Table = $TableName; Entity = @($Entity); OperationType = $OperationType }) }
        Mock Start-CIPPOrchestrator {}
        Mock Write-LogMessage {}
        Mock New-GraphPOSTRequest {}
        Mock Get-CippAuditLogNextAttempt { [datetime]'2030-01-01' }
        Mock Get-CIPPAuditLogPrefilter { $null }
        # Every candidate matches unless a test says otherwise; a match carries its raw record as AuditRecord JSON.
        Mock Test-CIPPAuditLogRules { [pscustomobject]@{ Error = $null; DataToProcess = @(foreach ($Row in $Rows) { [pscustomobject]@{ Id = $Row.Id; AuditRecord = [CIPP.CippJson]::ToJson($Row, 10) } }) } }
        # A listing and then its one blob per query; the real stream interleaves them in completion order.
        Mock Get-CIPPAuditLogContent {
            $script:Queries = $Queries
            foreach ($Query in $Queries) {
                $Blob = New-Blob $Query.TenantId $Query.ContentType
                New-Listing -Query $Query -Blobs @($Blob)
                New-Download $Blob @((New-Record 'rec-1'), (New-Record 'rec-2' 'Set-Mailbox'))
            }
        }
    }

    It 'stores the records unchanged, keyed by Id, in one feed partition' {
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        $Rows = @($script:Writes.Where({ $_.Table -eq 'CacheWebhooks' }).Entity)
        $Rows.RowKey | Should -Be @('rec-1', 'rec-2')
        @($Rows.PartitionKey | Select-Object -Unique) | Should -HaveCount 1
        $Rows[0].PartitionKey | Should -Match '^contoso\.com\|feed-\d{14}$'
        ($Rows[0].JSON | ConvertFrom-Json).Operation | Should -Be 'New-InboxRule'
        ($Rows[0].JSON | ConvertFrom-Json).PSObject.Properties.Name | Should -Not -Contain 'auditData'
    }

    It 'writes the feed window already Processing and returns it for the post-execution' {
        $Returned = @(Push-AuditLogFeedV3 -Item (New-FeedItem))
        $Ledger = @($script:Writes.Where({ $_.Table -eq 'AuditLogCoverage' }).Entity)[-1]
        $Ledger.State | Should -Be 'Processing'
        $Ledger.Type | Should -Be 'Feed'
        $Ledger.CandidateCount | Should -Be 2
        $Cache = @($script:Writes.Where({ $_.Table -eq 'CacheWebhooks' }).Entity)[0]
        $Cache.PartitionKey | Should -Be ('contoso.com|{0}' -f $Ledger.SearchId)
        $Returned.TenantFilter | Should -Be @('contoso.com')
        $Returned[0].SearchId | Should -Be $Ledger.SearchId
        $Returned[0].WindowRowKey | Should -Be $Ledger.RowKey
        $Returned[0].RecordCount | Should -Be 2
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }

    It 'hands each tenant its prefilter for the download to apply' {
        Mock Get-CIPPAuditLogPrefilter { [pscustomobject]@{ Rules = @(); Operations = $null; Tenant = $TenantFilter } }
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        Should -Invoke Get-CIPPAuditLogPrefilter -Times 1 -Exactly
        Should -Invoke Get-CIPPAuditLogContent -Times 1 -Exactly -ParameterFilter { $Prefilters['tid-1'].Tenant -eq 'contoso.com' }
    }

    It 'stores blobs that arrive before their listing, and counts every blob' {
        Mock Get-CIPPAuditLogContent {
            $Query = $Queries[0]
            $Blobs = @(foreach ($n in 1..70) { New-Blob $Query.TenantId $Query.ContentType "b$n" })
            foreach ($Blob in $Blobs) { New-Download $Blob @(New-Record "rec-$($Blob.contentId)") }
            New-Listing -Query $Query -Blobs $Blobs
        }
        $Returned = @(Push-AuditLogFeedV3 -Item (New-FeedItem))
        @($script:Writes.Where({ $_.Table -eq 'CacheWebhooks' }).Entity) | Should -HaveCount 70
        @($script:Writes.Where({ $_.Table -eq 'AuditLogCoverage' }).Entity)[-1].CandidateCount | Should -Be 70
        @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[0].Blobs | Should -Be 70
        $Returned.TenantFilter | Should -Be @('contoso.com')
    }

    It 'evaluates interleaved blobs against each tenant''s own directory memo, dropping it after the tenant''s last blob' {
        # Blobs of two tenants arrive interleaved; the engine reads the memo for the tenant it is evaluating.
        $script:SeenMemos = [System.Collections.Generic.List[string]]::new()
        Mock Test-CIPPAuditLogRules {
            $script:SeenMemos.Add(('{0}>{1}>{2}' -f $TenantFilter, $script:AuditRuleSearchLookups.Tenant, [int]$script:AuditRuleSearchLookups.UserLookup.Count))
            $script:AuditRuleSearchLookups.UserLookup = @{ $TenantFilter = 1 }
            [pscustomobject]@{ Error = $null; DataToProcess = @() }
        }
        Mock Get-CIPPAuditLogContent {
            $A = New-Blob 'tid-1' 'Audit.Exchange' 'a'; $B = New-Blob 'tid-2' 'Audit.Exchange' 'b'
            New-Download $A @(New-Record 'a1'); New-Download $B @(New-Record 'b1')
            $Last = New-Download $A @(New-Record 'a2'); $Last.TenantDone = $true; $Last
            $Again = New-Download (New-Blob 'tid-1' 'Audit.Exchange' 'c') @(New-Record 'a3'); $Again
        }
        $Item = [pscustomobject]@{ Tenants = @(
                [pscustomobject]@{ TenantFilter = 'contoso.com'; TenantId = 'tid-1'; ContentTypes = @('Audit.Exchange'); Cursors = @{} }
                [pscustomobject]@{ TenantFilter = 'fabrikam.com'; TenantId = 'tid-2'; ContentTypes = @('Audit.Exchange'); Cursors = @{} }
            ) }
        $null = Push-AuditLogFeedV3 -Item $Item
        # contoso's second blob reuses what its first loaded; after its last blob a later one starts from an empty memo.
        $script:SeenMemos | Should -Be @('contoso.com>contoso.com>0', 'fabrikam.com>fabrikam.com>0', 'contoso.com>contoso.com>1', 'contoso.com>contoso.com>0')
        $script:AuditRuleSearchLookups | Should -BeNullOrEmpty
    }

    It 'advances the cursor to the listing end and clears the backoff' {
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        $Cursor = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[0]
        $Cursor.LastEndUtc | Should -Be $script:Queries[0].EndTime
        $Cursor.Attempts | Should -Be 0
    }

    It 'reads the last hour for a new cursor' {
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        ($script:Queries[0].EndTime - $script:Queries[0].StartTime).TotalMinutes | Should -Be 60
    }

    It 'reads at most 24 hours from an old cursor and never past 7 days' {
        Push-AuditLogFeedV3 -Item (New-FeedItem -Cursors @{ 'Audit.Exchange' = @{ LastEndUtc = [datetime]::UtcNow.AddDays(-10) } })
        $Query = $script:Queries[0]
        $Query.StartTime | Should -BeGreaterThan ([datetime]::UtcNow.AddDays(-7))
        ($Query.EndTime - $Query.StartTime).TotalHours | Should -Be 24
        Should -Invoke Write-LogMessage -ParameterFilter { $message -like '*older than 7 days*' }
    }

    It 'keeps the cursor and backs off when the listing fails, logging the first failure only' {
        Mock Get-CIPPAuditLogContent { foreach ($Query in $Queries) { New-Listing -Query $Query -ErrorCode 'AF429' -ErrorMessage 'Too many requests' } }
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        Push-AuditLogFeedV3 -Item (New-FeedItem -Cursors @{ 'Audit.Exchange' = @{ Attempts = 1; LastErrorCode = 'AF429' } })
        $Cursors = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)
        $Cursors.Keys | Should -Not -Contain 'LastEndUtc'
        $Cursors[1].Attempts | Should -Be 2
        $Cursors[1].NextAttemptUtc | Should -Be ([datetime]'2030-01-01')
        Should -Invoke Write-LogMessage -Times 1 -Exactly
        $script:Writes.Where({ $_.Table -eq 'CacheWebhooks' }) | Should -HaveCount 0
    }

    It 'starts the subscription on AF20022 and moves the cursor to the listing end' {
        Mock Get-CIPPAuditLogContent { $script:Queries = $Queries; foreach ($Query in $Queries) { New-Listing -Query $Query -ErrorCode 'AF20022' -ErrorMessage 'No subscription found' } }
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/subscriptions/start?contentType=Audit.Exchange&PublisherIdentifier=*' }
        $Cursor = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[0]
        $Cursor.LastEndUtc | Should -Be $script:Queries[0].EndTime
        $Cursor.SubscriptionStartedUtc | Should -Not -BeNullOrEmpty
    }

    It 'keeps the cursor when the records cannot be stored' {
        Mock Add-CIPPAzDataTableEntity {
            if ($TableName -eq 'CacheWebhooks') { throw 'table unavailable' }
            $script:Writes.Add([pscustomobject]@{ Table = $TableName; Entity = @($Entity); OperationType = $OperationType })
        }
        $Returned = @(Push-AuditLogFeedV3 -Item (New-FeedItem))
        $Cursor = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[0]
        $Cursor.Keys | Should -Not -Contain 'LastEndUtc'
        $Cursor.LastErrorCode | Should -Be 'Store'
        $Returned | Should -HaveCount 0
    }

    It 'downloads every tenant in one call and stores each tenant in its own partition' {
        Mock Get-CIPPAuditLogContent {
            foreach ($Query in $Queries) { $Blob = New-Blob $Query.TenantId $Query.ContentType; New-Listing -Query $Query -Blobs @($Blob); New-Download $Blob @(New-Record "rec-$($Query.TenantId)") }
        }
        $Item = [pscustomobject]@{ Tenants = @(
                [pscustomobject]@{ TenantFilter = 'contoso.com'; TenantId = 'tid-1'; ContentTypes = @('Audit.Exchange'); Cursors = @{} }
                [pscustomobject]@{ TenantFilter = 'fabrikam.com'; TenantId = 'tid-2'; ContentTypes = @('Audit.Exchange'); Cursors = @{} }
            ) }
        $Returned = @(Push-AuditLogFeedV3 -Item $Item)
        Should -Invoke Get-CIPPAuditLogContent -Times 1 -Exactly
        $Rows = @($script:Writes.Where({ $_.Table -eq 'CacheWebhooks' }).Entity)
        ($Rows.Where({ $_.RowKey -eq 'rec-tid-2' }))[0].PartitionKey | Should -Match '^fabrikam\.com\|feed-'
        ($Rows.Where({ $_.RowKey -eq 'rec-tid-1' }))[0].PartitionKey | Should -Match '^contoso\.com\|feed-'
        $Returned.TenantFilter | Sort-Object | Should -Be @('contoso.com', 'fabrikam.com')
    }

    It 'holds back only the content type whose blob failed' {
        Mock Get-CIPPAuditLogContent {
            foreach ($Query in $Queries) {
                $Blob = New-Blob $Query.TenantId $Query.ContentType
                New-Listing -Query $Query -Blobs @($Blob)
                if ($Blob.contentType -eq 'Audit.Exchange') { New-Download $Blob -ErrorMessage 'expired' -ErrorCode 'AF20051' }
                else { New-Download $Blob @(New-Record 'rec-9') }
            }
        }
        Push-AuditLogFeedV3 -Item (New-FeedItem -ContentTypes @('Audit.AzureActiveDirectory', 'Audit.Exchange'))
        $Cursors = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)
        ($Cursors.Where({ $_.RowKey -eq 'Audit.AzureActiveDirectory' }))[0].Keys | Should -Contain 'LastEndUtc'
        ($Cursors.Where({ $_.RowKey -eq 'Audit.Exchange' }))[0].LastErrorCode | Should -Be 'AF20051'
        @($script:Writes.Where({ $_.Table -eq 'CacheWebhooks' }).Entity).RowKey | Should -Be @('rec-9')
    }

    It 'stores only the records the rule engine matches, evaluated once per tenant without dispatch' {
        Mock Test-CIPPAuditLogRules { [pscustomobject]@{ Error = $null; DataToProcess = @(foreach ($Row in $Rows) { if ($Row.Operation -eq 'New-InboxRule') { [pscustomobject]@{ Id = $Row.Id; AuditRecord = [CIPP.CippJson]::ToJson($Row, 10) }; [pscustomobject]@{ Id = $Row.Id; AuditRecord = [CIPP.CippJson]::ToJson($Row, 10) } } }) } }
        $Returned = @(Push-AuditLogFeedV3 -Item (New-FeedItem))
        @($script:Writes.Where({ $_.Table -eq 'CacheWebhooks' }).Entity.RowKey) | Should -Be @('rec-1')
        Should -Invoke Test-CIPPAuditLogRules -Times 1 -Exactly -ParameterFilter { $EvaluateOnly -and $TenantFilter -eq 'contoso.com' -and @($Rows).Count -eq 2 }
        $Ledger = @($script:Writes.Where({ $_.Table -eq 'AuditLogCoverage' }).Entity)[-1]
        $Ledger.EvaluatedCount | Should -Be 2
        $Ledger.CandidateCount | Should -Be 1
        $Returned[0].RecordCount | Should -Be 1
    }

    It 'stores no window when no rule matches' {
        Mock Test-CIPPAuditLogRules { [pscustomobject]@{ Error = $null; DataToProcess = @() } }
        $Returned = @(Push-AuditLogFeedV3 -Item (New-FeedItem))
        $Returned | Should -HaveCount 0
        @($script:Writes.Where({ $_.Table -eq 'CacheWebhooks' })) | Should -HaveCount 0
        @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' })) | Should -Not -BeNullOrEmpty
    }

    It 'stores every candidate when the rule engine fails, so processing decides' {
        Mock Test-CIPPAuditLogRules { [pscustomobject]@{ Error = 'lookup table unavailable'; DataToProcess = @() } }
        $null = Push-AuditLogFeedV3 -Item (New-FeedItem)
        (@($script:Writes.Where({ $_.Table -eq 'CacheWebhooks' }).Entity.RowKey) | Sort-Object) | Should -Be @('rec-1', 'rec-2')
    }

    It 'puts the window in the ledger as Storing before its first record is stored, so a crash leaves it for the sweep' {
        $null = Push-AuditLogFeedV3 -Item (New-FeedItem)
        $Tables = @($script:Writes.Table)
        $FirstLedger = [array]::IndexOf($Tables, 'AuditLogCoverage')
        $FirstLedger | Should -BeLessThan ([array]::IndexOf($Tables, 'CacheWebhooks'))
        $script:Writes[$FirstLedger].Entity[0].State | Should -Be 'Storing'
        @($script:Writes.Where({ $_.Table -eq 'AuditLogCoverage' }).Entity)[-1].State | Should -Be 'Processing'
    }

    It 'opens no window for a tenant nothing matched' {
        Mock Test-CIPPAuditLogRules { [pscustomobject]@{ Error = $null; DataToProcess = @() } }
        $null = Push-AuditLogFeedV3 -Item (New-FeedItem)
        @($script:Writes.Where({ $_.Table -eq 'AuditLogCoverage' })) | Should -HaveCount 0
    }
}
