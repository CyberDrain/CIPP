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
    function Test-CIPPAuditLogRules { param($TenantFilter, $Rows, [switch]$EvaluateOnly, [switch]$CallerSweepsCachePartition) }

    function New-FeedItem {
        param([hashtable]$Cursors = @{}, [string[]]$ContentTypes = @('Audit.Exchange'), [string]$CycleId)
        [pscustomobject]@{ CycleId = $CycleId; Tenants = @([pscustomobject]@{ TenantFilter = 'contoso.com'; TenantId = 'tid-1'; ContentTypes = $ContentTypes; Cursors = $Cursors }) }
    }
    function New-Listing {
        param($Query, [object[]]$Blobs = @(), $ErrorCode, $ErrorMessage, [bool]$Complete = $true)
        [pscustomobject]@{
            Kind = 'Listing'; TenantDone = $false; Complete = $Complete
            TenantFilter = $Query.TenantFilter; TenantId = $Query.TenantId; ContentType = $Query.ContentType
            StartTime = $Query.StartTime; EndTime = $Query.EndTime; Blobs = $Blobs; StatusCode = 200; ErrorCode = $ErrorCode; Error = $ErrorMessage
        }
    }
    function New-Blob([string]$TenantId, [string]$ContentType, [string]$Id = 'x', $Created) {
        [pscustomobject]@{ contentId = $Id; contentType = $ContentType; contentUri = "https://manage.office.com/api/v1.0/$TenantId/activity/feed/audit/$Id"; contentCreated = $(if ($Created) { $Created.ToString('o') }) }
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
        # Every candidate matches unless a test says otherwise.
        Mock Test-CIPPAuditLogRules { [pscustomobject]@{ Error = $null; MatchedLogs = @($Rows).Count } }
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

    It 'sends the alerts in place: the whole engine runs on each blob, nothing is staged or queued' {
        $Returned = @(Push-AuditLogFeedV3 -Item (New-FeedItem))
        Should -Invoke Test-CIPPAuditLogRules -Times 1 -Exactly -ParameterFilter { $CallerSweepsCachePartition -and -not $EvaluateOnly -and $TenantFilter -eq 'contoso.com' -and @($Rows).Count -eq 2 }
        @($script:Writes.Where({ $_.Table -in @('CacheWebhooks', 'AuditLogCoverage') })) | Should -HaveCount 0
        $Returned | Should -HaveCount 0
        Should -Invoke Start-CIPPOrchestrator -Times 0 -Exactly
    }

    It 'hands each tenant its prefilter for the download to apply, a few blobs at a time' {
        Mock Get-CIPPAuditLogPrefilter { [pscustomobject]@{ Rules = @(); Operations = $null; Tenant = $TenantFilter } }
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        Should -Invoke Get-CIPPAuditLogPrefilter -Times 1 -Exactly
        Should -Invoke Get-CIPPAuditLogContent -Times 1 -Exactly -ParameterFilter { $Prefilters['tid-1'].Tenant -eq 'contoso.com' -and $MaxConcurrency -eq 4 }
    }

    It 'counts blobs that arrive before their listing, and reaches the end of the range' {
        Mock Get-CIPPAuditLogContent {
            $script:Queries = $Queries
            $Query = $Queries[0]
            $Blobs = @(foreach ($n in 1..70) { New-Blob $Query.TenantId $Query.ContentType "b$n" })
            foreach ($Blob in $Blobs) { New-Download $Blob @(New-Record "rec-$($Blob.contentId)") }
            New-Listing -Query $Query -Blobs $Blobs
        }
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        Should -Invoke Test-CIPPAuditLogRules -Times 70 -Exactly
        $Cursor = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[-1]
        $Cursor.Blobs | Should -Be 70
        $Cursor.Matched | Should -Be 70
        $Cursor.LastEndUtc | Should -Be $script:Queries[0].EndTime
    }

    It 'skips the engine for a blob the prefilter emptied, and still counts it finished' {
        Mock Get-CIPPAuditLogContent { $script:Queries = $Queries; $Query = $Queries[0]; $Blob = New-Blob $Query.TenantId $Query.ContentType; New-Listing -Query $Query -Blobs @($Blob); New-Download $Blob @() }
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        Should -Invoke Test-CIPPAuditLogRules -Times 0 -Exactly
        @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[-1].LastEndUtc | Should -Be $script:Queries[0].EndTime
    }

    It 'stops the cursor just short of a blob the rule engine failed on, and backs off' {
        Mock Test-CIPPAuditLogRules { if (@($Rows)[0].Id -eq 'r2') { [pscustomobject]@{ Error = 'lookup table unavailable' } } else { [pscustomobject]@{ Error = $null; MatchedLogs = 1 } } }
        Mock Get-CIPPAuditLogContent {
            $script:Queries = $Queries
            $Query = $Queries[0]
            $Blobs = @(foreach ($n in 1..3) { New-Blob $Query.TenantId $Query.ContentType "b$n" $Query.StartTime.AddMinutes($n) })
            New-Listing -Query $Query -Blobs $Blobs
            foreach ($n in 0..2) { New-Download $Blobs[$n] @(New-Record "r$($n + 1)") }
        }
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        $Cursor = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[-1]
        $Cursor.LastErrorCode | Should -Be 'Rules'
        $Cursor.LastEndUtc | Should -Be $script:Queries[0].StartTime.AddMinutes(2).AddSeconds(-1)
    }

    It 'evaluates interleaved blobs against each tenant''s own directory memo, dropping it after the tenant''s last blob' {
        # Blobs of two tenants arrive interleaved; the engine reads the memo for the tenant it is evaluating.
        $script:SeenMemos = [System.Collections.Generic.List[string]]::new()
        Mock Test-CIPPAuditLogRules {
            $script:SeenMemos.Add(('{0}>{1}>{2}' -f $TenantFilter, $script:AuditRuleSearchLookups.Tenant, [int]$script:AuditRuleSearchLookups.UserLookup.Count))
            $script:AuditRuleSearchLookups.UserLookup = @{ $TenantFilter = 1 }
            [pscustomobject]@{ Error = $null; MatchedLogs = 0 }
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

    It 'records the task under its cycle and keeps the read''s counts on the cursor' {
        Push-AuditLogFeedV3 -Item (New-FeedItem -CycleId '20261024120000' -ContentTypes @('Audit.AzureActiveDirectory', 'Audit.Exchange'))
        $Cycle = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCycles' }).Entity)[0]
        $Cycle.RowKey | Should -Be '20261024120000-tid-1'
        $Cycle.Tenants | Should -Be 1
        $Cycle.Feeds | Should -Be 2
        $Cycle.Blobs | Should -Be 2
        $Cycle.Records | Should -Be 4
        $Cycle.Evaluated | Should -Be 4
        $Cycle.Matched | Should -Be 4
        $Cycle.Failed | Should -Be 0
        $Cursor = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[0]
        $Cursor.Records | Should -Be 2
        $Cursor.Matched | Should -Be 2
        $Cursor.LastSuccessUtc | Should -Not -BeNullOrEmpty
    }

    It 'writes no cycle row for an item without a cycle' {
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        $script:Writes.Where({ $_.Table -eq 'AuditLogFeedCycles' }) | Should -HaveCount 0
    }

    It 'reads the last hour for a new cursor' {
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        ($script:Queries[0].EndTime - $script:Queries[0].StartTime).TotalMinutes | Should -Be 60
    }

    It 'lists an old backlog in consecutive 24-hour ranges up to now, never past 7 days' {
        Push-AuditLogFeedV3 -Item (New-FeedItem -Cursors @{ 'Audit.Exchange' = @{ LastEndUtc = [datetime]::UtcNow.AddDays(-10) } })
        $script:Queries | Should -HaveCount 7
        $script:Queries[0].StartTime | Should -BeGreaterThan ([datetime]::UtcNow.AddDays(-7))
        foreach ($i in 0..5) {
            ($script:Queries[$i].EndTime - $script:Queries[$i].StartTime).TotalHours | Should -Be 24
            $script:Queries[$i + 1].StartTime | Should -Be $script:Queries[$i].EndTime
        }
        $script:Queries[-1].EndTime | Should -BeGreaterThan ([datetime]::UtcNow.AddMinutes(-6))
        @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[-1].LastEndUtc | Should -Be $script:Queries[-1].EndTime
        Should -Invoke Write-LogMessage -ParameterFilter { $message -like '*older than 7 days*' }
    }

    It 'saves the cursor every 10 finished blobs, just before the oldest listed blob not yet finished' {
        Mock Get-CIPPAuditLogContent {
            $script:Queries = $Queries
            $Query = $Queries[0]
            $Blobs = @(foreach ($n in 1..45) { New-Blob $Query.TenantId $Query.ContentType "b$n" $Query.StartTime.AddSeconds($n) })
            New-Listing -Query $Query -Blobs $Blobs
            # b21 arrives last, so it holds the cursor back until the end.
            foreach ($Blob in @($Blobs.Where({ $_.contentId -ne 'b21' })) + @($Blobs.Where({ $_.contentId -eq 'b21' }))) { New-Download $Blob @(New-Record "rec-$($Blob.contentId)") }
        }
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        $Cursors = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }))
        # At 10 finished b11 is the oldest left, at 20 b21, which then holds the cursor until it arrives.
        $Checkpoints = @($Cursors.Where({ $_.Entity[0].CheckpointUtc }))
        $Checkpoints | Should -HaveCount 2
        $Checkpoints[0].OperationType | Should -Be 'UpsertMerge'
        $Checkpoints.ForEach({ $_.Entity[0].LastEndUtc }) | Should -Be @($script:Queries[0].StartTime.AddSeconds(10), $script:Queries[0].StartTime.AddSeconds(20))
        $Cursors[-1].Entity[0].LastEndUtc | Should -Be $script:Queries[0].EndTime
    }

    It 'checkpoints a range whose listing is still paging, up to just before the newest blob listed so far' {
        Mock Get-CIPPAuditLogContent {
            $script:Queries = $Queries
            $Query = $Queries[0]
            $Page1 = @(foreach ($n in 1..10) { New-Blob $Query.TenantId $Query.ContentType "b$n" $Query.StartTime.AddSeconds($n) })
            New-Listing -Query $Query -Blobs $Page1 -Complete $false
            foreach ($Blob in $Page1) { New-Download $Blob @(New-Record "rec-$($Blob.contentId)") }
            $Page2 = @(New-Blob $Query.TenantId $Query.ContentType 'b11' $Query.StartTime.AddSeconds(11))
            New-Listing -Query $Query -Blobs $Page2
            New-Download $Page2[0] @(New-Record 'rec-b11')
        }
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        $Writes = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }))
        # Page 2 may still hold blobs published in the same second as b10, so the checkpoint stops a second short of it.
        @($Writes.Where({ $_.Entity[0].CheckpointUtc })).ForEach({ $_.Entity[0].LastEndUtc }) | Should -Be @($script:Queries[0].StartTime.AddSeconds(9))
        $Writes[-1].Entity[0].LastEndUtc | Should -Be $script:Queries[0].EndTime
        $Writes[-1].Entity[0].Blobs | Should -Be 11
    }

    It 'keeps the blobs finished before a failed one: the cursor stops just short of it and backs off' {
        Mock Get-CIPPAuditLogContent {
            $script:Queries = $Queries
            $Query = $Queries[0]
            $Blobs = @(foreach ($n in 1..3) { New-Blob $Query.TenantId $Query.ContentType "b$n" $Query.StartTime.AddMinutes($n) })
            New-Listing -Query $Query -Blobs $Blobs
            New-Download $Blobs[0] @(New-Record 'r1')
            New-Download $Blobs[1] -ErrorMessage 'blob expired' -ErrorCode 'AF20051'
            New-Download $Blobs[2] @(New-Record 'r3')
        }
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        $Cursor = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[-1]
        $Cursor.LastErrorCode | Should -Be 'AF20051'
        $Cursor.LastEndUtc | Should -Be $script:Queries[0].StartTime.AddMinutes(2).AddSeconds(-1)
        $Cursor.NextAttemptUtc | Should -Be ([datetime]'2030-01-01')
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
    }

    It 'starts the subscription on <Code> and moves the cursor to the listing end' -ForEach @(@{ Code = 'AF20022' }, @{ Code = 'AF20023' }) {
        Mock Get-CIPPAuditLogContent { $script:Queries = $Queries; foreach ($Query in $Queries) { New-Listing -Query $Query -ErrorCode $Code -ErrorMessage 'No subscription found' } }
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*/subscriptions/start?contentType=Audit.Exchange&PublisherIdentifier=*' }
        $Cursor = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[0]
        $Cursor.LastEndUtc | Should -Be $script:Queries[0].EndTime
        $Cursor.SubscriptionStartedUtc | Should -Not -BeNullOrEmpty
    }

    It 'parks the cursor for a day with a warning when the tenant has no audit log (<Case>)' -ForEach @(
        @{ Case = 'audit log off'; Code = 'AuditLogDisabled'; ErrorCode = 'AF20023'; ErrorMessage = 'The subscription was disabled.'; StartError = 'DataServiceException: Tenant tid-1 does not exist.' }
        @{ Case = 'service principal disabled'; Code = 'NoAuditLog'; ErrorCode = 'Token'; ErrorMessage = 'Could not get token: invalid_resource:AADSTS500014: The service principal for resource is disabled.'; StartError = $null }
    ) {
        Mock Get-CIPPAuditLogContent { foreach ($Query in $Queries) { New-Listing -Query $Query -ErrorCode $ErrorCode -ErrorMessage $ErrorMessage } }
        if ($StartError) { Mock New-GraphPOSTRequest { throw $StartError } }
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        $Cursor = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[0]
        $Cursor.Keys | Should -Not -Contain 'LastEndUtc'
        $Cursor.LastErrorCode | Should -Be $Code
        ($Cursor.NextAttemptUtc - [datetime]::UtcNow).TotalHours | Should -BeGreaterThan 23
        Should -Invoke Get-CippAuditLogNextAttempt -Times 0 -Exactly
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Warning' }
    }

    It 'downloads every tenant in one call and evaluates each against its own rules' {
        Mock Get-CIPPAuditLogContent {
            foreach ($Query in $Queries) { $Blob = New-Blob $Query.TenantId $Query.ContentType; New-Listing -Query $Query -Blobs @($Blob); New-Download $Blob @(New-Record "rec-$($Query.TenantId)") }
        }
        $Item = [pscustomobject]@{ Tenants = @(
                [pscustomobject]@{ TenantFilter = 'contoso.com'; TenantId = 'tid-1'; ContentTypes = @('Audit.Exchange'); Cursors = @{} }
                [pscustomobject]@{ TenantFilter = 'fabrikam.com'; TenantId = 'tid-2'; ContentTypes = @('Audit.Exchange'); Cursors = @{} }
            ) }
        $null = Push-AuditLogFeedV3 -Item $Item
        Should -Invoke Get-CIPPAuditLogContent -Times 1 -Exactly
        Should -Invoke Test-CIPPAuditLogRules -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'contoso.com' -and @($Rows)[0].Id -eq 'rec-tid-1' }
        Should -Invoke Test-CIPPAuditLogRules -Times 1 -Exactly -ParameterFilter { $TenantFilter -eq 'fabrikam.com' -and @($Rows)[0].Id -eq 'rec-tid-2' }
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
        Should -Invoke Test-CIPPAuditLogRules -Times 1 -Exactly
    }

    It 'advances the cursor with nothing matched when no rule matches' {
        Mock Test-CIPPAuditLogRules { [pscustomobject]@{ Error = $null; MatchedLogs = 0 } }
        Push-AuditLogFeedV3 -Item (New-FeedItem)
        $Cursor = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[-1]
        $Cursor.LastEndUtc | Should -Be $script:Queries[0].EndTime
        $Cursor.Matched | Should -Be 0
    }
}
