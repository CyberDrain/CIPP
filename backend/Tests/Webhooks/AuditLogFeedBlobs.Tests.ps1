# Pester tests for the audit log feed's blob pipeline: the round window, listing into AuditLogFeedBlobs, the bounded
# fan-out of batch runs, the batch task and the cursor post-execution.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CippTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force, $OperationType) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Get-CIPPAuditLogContent { param($Queries, $Blobs, [switch]$ListOnly, $Prefilters, $MaxConcurrency) }
    function Get-CIPPAuditLogPrefilter { param($TenantFilter) }
    function Get-CippAuditLogNextAttempt { param($Attempts) }
    function New-GraphPOSTRequest { param($type, $uri, $body, $scope, $tenantid, $NoAuthCheck) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Test-CIPPAuditLogRules { param($TenantFilter, $Rows, [switch]$EvaluateOnly, [switch]$CallerSweepsCachePartition, $AlertCounts) }
    foreach ($Name in 'Get-CIPPAuditLogFeedWindow', 'Push-AuditLogFeedListV3', 'Push-AuditLogFeedFanOutV3', 'Push-AuditLogFeedBlobsV3', 'Push-AuditLogFeedCursorV3') {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/Webhooks/$Name.ps1")
    }

    function New-Row([string]$Tenant, [datetime]$Created, [string]$Id, [int]$Attempts = 0, $Queued) {
        [pscustomobject]@{ PartitionKey = $Tenant; RowKey = '{0:D19}${1}' -f $Created.ToUniversalTime().Ticks, $Id; TenantId = "id-$Tenant"; ContentType = 'Audit.Exchange'; ContentUri = "https://manage.office.com/blob/$Id"; Attempts = $Attempts; LastQueuedUtc = $Queued }
    }
}

Describe 'Get-CIPPAuditLogFeedWindow' {
    BeforeAll { $script:Now = ([datetime]'2026-10-24T12:00:00Z').ToUniversalTime() }

    It 'reads the same window whatever the kind of the time it is given' {
        $Local = Get-CIPPAuditLogFeedWindow -LastEndUtc $script:Now.AddHours(-5) -Now $script:Now.ToLocalTime()
        $Local.Start | Should -Be $script:Now.AddHours(-5)
        $Local.End | Should -Be $script:Now.AddHours(-2)
    }

    It 'reads the last hour for a new cursor' {
        $Window = Get-CIPPAuditLogFeedWindow -LastEndUtc $null -Now $script:Now
        $Window.Start | Should -Be $script:Now.AddMinutes(-65)
        $Window.End | Should -Be $script:Now.AddMinutes(-5)
    }

    It 'reads at most 3 hours from the cursor' {
        $Window = Get-CIPPAuditLogFeedWindow -LastEndUtc $script:Now.AddHours(-5) -Now $script:Now
        $Window.Start | Should -Be $script:Now.AddHours(-5)
        $Window.End | Should -Be $script:Now.AddHours(-2)
        $Window.Skipped | Should -BeNullOrEmpty
    }

    It 'goes no further back than 6 hours, and says from where it skipped' {
        $Window = Get-CIPPAuditLogFeedWindow -LastEndUtc $script:Now.AddDays(-3) -Now $script:Now
        $Window.Start | Should -Be $script:Now.AddHours(-6)
        $Window.End | Should -Be $script:Now.AddHours(-3)
        $Window.Skipped | Should -Be $script:Now.AddDays(-3)
    }

    It 'has nothing to read for a cursor in the last 5 minutes' {
        Get-CIPPAuditLogFeedWindow -LastEndUtc $script:Now.AddMinutes(-3) -Now $script:Now | Should -BeNullOrEmpty
    }
}

Describe 'Push-AuditLogFeedListV3' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add([pscustomobject]@{ Table = $TableName; Entity = @($Entity); OperationType = $OperationType }) }
        Mock Write-LogMessage {}
        Mock New-GraphPOSTRequest {}
        Mock Get-CippAuditLogNextAttempt { [datetime]'2030-01-01' }
        $script:Pages = { param($Queries) foreach ($Query in $Queries) { [pscustomobject]@{ Kind = 'Listing'; TenantFilter = $Query.TenantFilter; TenantId = $Query.TenantId; ContentType = $Query.ContentType; Complete = $true; Blobs = @([pscustomobject]@{ contentId = "c-$($Query.ContentType)"; contentUri = 'https://manage.office.com/b'; contentCreated = '2026-10-24T10:00:00Z' }); ErrorCode = $null; Error = $null } } }
        Mock Get-CIPPAuditLogContent { $script:Asked = $Queries; & $script:Pages $Queries }
    }

    It 'lists every due feed of the group at once and records one row per blob, keyed to sort oldest first' {
        $Item = [pscustomobject]@{ Tenants = @(
                [pscustomobject]@{ TenantFilter = 'a.com'; TenantId = 'id-a'; ContentTypes = @('Audit.Exchange', 'Audit.AzureActiveDirectory'); Cursors = @{} }
                [pscustomobject]@{ TenantFilter = 'b.com'; TenantId = 'id-b'; ContentTypes = @('Audit.Exchange'); Cursors = @{} }
            ) }
        Push-AuditLogFeedListV3 -Item $Item
        Should -Invoke Get-CIPPAuditLogContent -Times 1 -Exactly -ParameterFilter { $ListOnly -and $MaxConcurrency -eq 20 -and @($Queries).Count -eq 3 }
        $Rows = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedBlobs' }).Entity)
        $Rows | Should -HaveCount 3
        $Rows[0].RowKey | Should -Be ('{0:D19}$c-Audit.Exchange' -f ([datetime]'2026-10-24T10:00:00Z').ToUniversalTime().Ticks)
        $Rows[0].ContentUri | Should -Be 'https://manage.office.com/b'
    }

    It 'lists from ListedThroughUtc and moves it to the end of the window once the listing is complete' {
        $Listed = [datetime]::UtcNow.AddHours(-2)
        Push-AuditLogFeedListV3 -Item ([pscustomobject]@{ Tenants = @([pscustomobject]@{ TenantFilter = 'a.com'; TenantId = 'id-a'; ContentTypes = @('Audit.Exchange'); Cursors = @{ 'Audit.Exchange' = @{ LastEndUtc = [datetime]::UtcNow.AddHours(-5); ListedThroughUtc = $Listed } } }) })
        $script:Asked[0].StartTime | Should -Be $Listed
        $Cursor = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[0]
        $Cursor.ListedThroughUtc | Should -Be $script:Asked[0].EndTime
        $Cursor.Attempts | Should -Be 0
    }

    It 'keeps ListedThroughUtc on a listing that fails or stops part way, and backs off' {
        $script:Pages = { param($Queries) [pscustomobject]@{ Kind = 'Listing'; TenantFilter = 'a.com'; TenantId = 'id-a'; ContentType = 'Audit.Exchange'; Complete = $true; Blobs = @(); ErrorCode = 'AF429'; Error = 'Too many requests' } }
        Push-AuditLogFeedListV3 -Item ([pscustomobject]@{ Tenants = @([pscustomobject]@{ TenantFilter = 'a.com'; TenantId = 'id-a'; ContentTypes = @('Audit.Exchange'); Cursors = @{} }) })
        $Cursor = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[0]
        $Cursor.Keys | Should -Not -Contain 'ListedThroughUtc'
        $Cursor.LastErrorCode | Should -Be 'AF429'
        $Cursor.NextAttemptUtc | Should -Be ([datetime]'2030-01-01')
    }

    It 'reads the cursors of a payload as the orchestrator delivers it, deserialised from JSON' {
        $script:Pages = { param($Queries) [pscustomobject]@{ Kind = 'Listing'; TenantFilter = 'a.com'; TenantId = 'id-a'; ContentType = 'Audit.Exchange'; Complete = $true; Blobs = @(); ErrorCode = 'AF429'; Error = 'Too many requests' } }
        $Listed = [datetime]::UtcNow.AddHours(-2)
        $Item = [pscustomobject]@{ Tenants = @([pscustomobject]@{ TenantFilter = 'a.com'; TenantId = 'id-a'; ContentTypes = @('Audit.Exchange'); Cursors = @{ 'Audit.Exchange' = @{ ListedThroughUtc = $Listed.ToString('o'); Attempts = 2; LastErrorCode = 'AF429' } } }) } | ConvertTo-Json -Depth 6 | ConvertFrom-Json
        Push-AuditLogFeedListV3 -Item $Item
        ([datetimeoffset]$script:Asked[0].StartTime).UtcDateTime | Should -Be $Listed
        @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[0].Attempts | Should -Be 3
    }

    It 'starts a missing subscription and moves on' {
        $script:Pages = { param($Queries) [pscustomobject]@{ Kind = 'Listing'; TenantFilter = 'a.com'; TenantId = 'id-a'; ContentType = 'Audit.Exchange'; Complete = $true; Blobs = @(); ErrorCode = 'AF20022'; Error = 'No subscription' } }
        Push-AuditLogFeedListV3 -Item ([pscustomobject]@{ Tenants = @([pscustomobject]@{ TenantFilter = 'a.com'; TenantId = 'id-a'; ContentTypes = @('Audit.Exchange'); Cursors = @{} }) })
        Should -Invoke New-GraphPOSTRequest -Times 1 -Exactly -ParameterFilter { $uri -like '*subscriptions/start?contentType=Audit.Exchange*' }
        @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[0].ListedThroughUtc | Should -Not -BeNullOrEmpty
    }

    It 'parks a tenant with no audit log for a day' {
        $script:Pages = { param($Queries) [pscustomobject]@{ Kind = 'Listing'; TenantFilter = 'a.com'; TenantId = 'id-a'; ContentType = 'Audit.Exchange'; Complete = $true; Blobs = @(); ErrorCode = 'Token'; Error = 'AADSTS500014: disabled' } }
        Push-AuditLogFeedListV3 -Item ([pscustomobject]@{ Tenants = @([pscustomobject]@{ TenantFilter = 'a.com'; TenantId = 'id-a'; ContentTypes = @('Audit.Exchange'); Cursors = @{} }) })
        $Cursor = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCursor' }).Entity)[0]
        $Cursor.LastErrorCode | Should -Be 'NoAuditLog'
        $Cursor.NextAttemptUtc | Should -BeGreaterThan ([datetime]::UtcNow.AddHours(23))
    }
}

Describe 'Push-AuditLogFeedFanOutV3' {
    BeforeEach {
        $script:Rows = @()
        $script:Started = [System.Collections.Generic.List[object]]::new()
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Removed = [System.Collections.Generic.List[object]]::new()
        Mock Get-CIPPAzDataTableEntity { $script:Rows }
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add(@($Entity)) }
        Mock Remove-CIPPAzDataTableEntity { $script:Removed.Add(@($Entity)) }
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject) }
        Mock Write-LogMessage {}
        Mock Push-AuditLogFeedCursorV3 {}
        $script:Start = [datetime]::UtcNow.AddMinutes(-1)
        $script:Params = @{ CycleId = 'c1'; CycleStartUtc = $script:Start.ToString('o'); Run = 0 }
    }

    It 'queues at most 80 tasks of 64 rows, tenants together and oldest first, counting an attempt on each row it queues' {
        $Base = [datetime]'2026-10-24T08:00:00Z'
        $script:Rows = @(foreach ($n in 1..6000) { New-Row -Tenant ('t{0:D2}.com' -f ($n % 7)) -Created $Base.AddSeconds($n) -Id "b$n" })
        Push-AuditLogFeedFanOutV3 -Item @{ Parameters = $script:Params }
        $Run = $script:Started[0]
        $Run.OrchestratorName | Should -Be 'AuditLogFeedBlobsV3'
        $Run.Batch | Should -HaveCount 80
        @($Run.Batch[0].Tenants.Blobs).Count | Should -Be 64
        $Run.Batch[0].Tenants[0].TenantFilter | Should -Be 't00.com'
        $Run.PostExecution.FunctionName | Should -Be 'AuditLogFeedCursorV3'
        $Run.PostExecution.Parameters.Run | Should -Be 1
        $Marked = @($script:Writes | ForEach-Object { $_ })
        $Marked | Should -HaveCount (80 * 64)
        $Marked[0].Attempts | Should -Be 1
        $Marked[0].LastQueuedUtc | Should -Not -BeNullOrEmpty
        # A task's payload stays well inside the orchestrator's 64 KB.
        ([System.Text.Encoding]::UTF8.GetByteCount((ConvertTo-Json -InputObject $Run.Batch[0] -Depth 6 -Compress))) | Should -BeLessThan 30KB
    }

    It 'names a later run of the cycle into the family and skips rows already queued this cycle' {
        $script:Params.Run = 2
        $script:Rows = @(
            New-Row -Tenant 'a.com' -Created ([datetime]'2026-10-24T08:00:00Z') -Id 'queued' -Attempts 1 -Queued ([datetime]::UtcNow)
            New-Row -Tenant 'a.com' -Created ([datetime]'2026-10-24T08:00:01Z') -Id 'fresh'
            New-Row -Tenant 'a.com' -Created ([datetime]'2026-10-24T08:00:02Z') -Id 'earlier-cycle' -Attempts 1 -Queued ($script:Start.AddMinutes(-15))
        )
        Push-AuditLogFeedFanOutV3 -Item @{ Parameters = $script:Params }
        $Run = $script:Started[0]
        $Run.OrchestratorName | Should -Match '^AuditLogFeedBlobsV3-[0-9a-f-]{36}$'
        $Run.AllowCollision | Should -BeTrue
        @($Run.Batch[0].Tenants.Blobs.RowKey | ForEach-Object { ($_ -split '\$', 2)[1] }) | Should -Be @('fresh', 'earlier-cycle')
    }

    It 'drops a row queued 5 times with an error, and moves the cursors when nothing is left to queue' {
        $script:Rows = @(New-Row -Tenant 'a.com' -Created ([datetime]'2026-10-24T08:00:00Z') -Id 'bad' -Attempts 5)
        Push-AuditLogFeedFanOutV3 -Item @{ Parameters = $script:Params }
        $script:Started | Should -HaveCount 0
        @($script:Removed[0]).Count | Should -Be 1
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' -and $tenant -eq 'a.com' }
        Should -Invoke Push-AuditLogFeedCursorV3 -Times 1 -Exactly -ParameterFilter { -not $Item.Parameters.Run }
    }
}

Describe 'Push-AuditLogFeedBlobsV3' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Removed = [System.Collections.Generic.List[object]]::new()
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add([pscustomobject]@{ Table = $TableName; Entity = @($Entity); OperationType = $OperationType }) }
        Mock Remove-CIPPAzDataTableEntity { $script:Removed.Add(@($Entity)) }
        Mock Get-CIPPAuditLogPrefilter { @{ Tenant = $TenantFilter } }
        Mock Test-CIPPAuditLogRules { [pscustomobject]@{ Error = $(if ($TenantFilter -eq 'bad.com') { 'engine failed' }); MatchedLogs = @($Rows).Count; AlertMs = 0 } }
        Mock Get-CIPPAuditLogContent {
            foreach ($Blob in $Blobs) {
                $Error = if ($Blob.RowKey -eq 'r-404') { 'Not found' }
                [pscustomobject]@{ Kind = 'Blob'; TenantId = $Blob.TenantId; Blob = $Blob; Skipped = $false; RecordCount = 1; Records = @([pscustomobject]@{ Id = $Blob.RowKey }); ParseMs = 0; Error = $Error; ErrorCode = $null; TenantDone = $false }
            }
        }
    }

    It 'downloads the batch 16 at a time with each tenant''s prefilter, deletes finished rows and keeps failed ones with the error' {
        $Item = [pscustomobject]@{ CycleId = 'c1'; Tenants = @(
                [pscustomobject]@{ TenantFilter = 'a.com'; TenantId = 'id-a'; Blobs = @([pscustomobject]@{ RowKey = 'r-1'; ContentType = 'Audit.Exchange'; contentUri = 'u1' }, [pscustomobject]@{ RowKey = 'r-404'; ContentType = 'Audit.Exchange'; contentUri = 'u2' }) }
                [pscustomobject]@{ TenantFilter = 'bad.com'; TenantId = 'id-bad'; Blobs = @([pscustomobject]@{ RowKey = 'r-3'; ContentType = 'Audit.Exchange'; contentUri = 'u3' }) }
            ) }
        Push-AuditLogFeedBlobsV3 -Item $Item
        Should -Invoke Get-CIPPAuditLogContent -Times 1 -Exactly -ParameterFilter { $MaxConcurrency -eq 16 -and @($Blobs).Count -eq 3 -and $Prefilters['id-a'].Tenant -eq 'a.com' }
        @($script:Removed[0].RowKey) | Should -Be @('r-1')
        $Failed = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedBlobs' }).Entity)
        @($Failed.RowKey) | Should -Be @('r-404', 'r-3')
        $Failed[1].LastError | Should -Be 'engine failed'
        $Cycle = @($script:Writes.Where({ $_.Table -eq 'AuditLogFeedCycles' }).Entity)[0]
        $Cycle.Blobs | Should -Be 3
        $Cycle.Failed | Should -Be 2
    }
}

Describe 'Push-AuditLogFeedCursorV3' {
    BeforeEach {
        $script:Writes = [System.Collections.Generic.List[object]]::new()
        $script:Pending = @()
        $script:Cursors = @()
        $script:Expired = @()
        Mock Get-CIPPAzDataTableEntity { switch ($TableName) { 'AuditLogFeedBlobs' { $script:Pending } 'AuditLogFeedThresholds' { $script:Expired } default { $script:Cursors } } }
        Mock Add-CIPPAzDataTableEntity { $script:Writes.Add(@($Entity)) }
        Mock Remove-CIPPAzDataTableEntity {}
        Mock Push-AuditLogFeedFanOutV3 {}
    }

    It 'moves each feed to just before its oldest pending blob, or to where it was listed through' {
        $Listed = [datetime]'2026-10-24T11:00:00Z'
        $script:Cursors = @(
            [pscustomobject]@{ PartitionKey = 'a.com'; RowKey = 'Audit.Exchange'; ListedThroughUtc = $Listed; LastEndUtc = [datetime]'2026-10-24T08:00:00Z' }
            [pscustomobject]@{ PartitionKey = 'b.com'; RowKey = 'Audit.Exchange'; ListedThroughUtc = $Listed; LastEndUtc = [datetime]'2026-10-24T08:00:00Z' }
            [pscustomobject]@{ PartitionKey = 'c.com'; RowKey = 'Audit.Exchange'; LastEndUtc = [datetime]'2026-10-24T08:00:00Z' }
        )
        $script:Pending = @(
            New-Row -Tenant 'a.com' -Created ([datetime]'2026-10-24T09:30:00Z') -Id 'later'
            New-Row -Tenant 'a.com' -Created ([datetime]'2026-10-24T09:00:00Z') -Id 'oldest'
        )
        Push-AuditLogFeedCursorV3 -Item @{ Parameters = @{ CycleId = 'c1' } }
        $Updates = @($script:Writes[0])
        $Updates | Should -HaveCount 2
        $Updates.Where({ $_.PartitionKey -eq 'a.com' })[0].LastEndUtc | Should -Be ([datetime]'2026-10-24T08:59:59Z').ToUniversalTime()
        $Updates.Where({ $_.PartitionKey -eq 'a.com' })[0].LastEndUtc.Kind | Should -Be 'Utc'
        $Updates.Where({ $_.PartitionKey -eq 'b.com' })[0].LastEndUtc | Should -Be $Listed.ToUniversalTime()
        Should -Invoke Push-AuditLogFeedFanOutV3 -Times 0 -Exactly
    }

    It 'removes threshold rows older than 12 hours' {
        $script:Expired = @([pscustomobject]@{ PartitionKey = 'id-a'; RowKey = 'rule-1|bob|2026-10-24T17:0|r1' })
        Push-AuditLogFeedCursorV3 -Item @{ Parameters = @{ CycleId = 'c1' } }
        Should -Invoke Get-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'AuditLogFeedThresholds' -and $Filter -like 'Timestamp lt datetime*' } -Times 1 -Exactly
        Should -Invoke Remove-CIPPAzDataTableEntity -ParameterFilter { $TableName -eq 'AuditLogFeedThresholds' -and @($Entity).Count -eq 1 } -Times 1 -Exactly
    }

    It 'queues the cycle''s next run after a blob run' {
        Push-AuditLogFeedCursorV3 -Item @{ Parameters = @{ CycleId = 'c1'; CycleStartUtc = 'x'; Run = 1 } }
        Should -Invoke Push-AuditLogFeedFanOutV3 -Times 1 -Exactly -ParameterFilter { $Item.Parameters.Run -eq 1 }
    }
}
