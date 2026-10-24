# Pester tests for Push-AuditLogFeedProcessV3 - the feed run's post-execution.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-CippQueueEntry { param($Name, $Reference, $TotalTasks) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Get-CippTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property) }
    function Get-CIPPAuditLogTenantScope {}
    function Start-CIPPAuditLogFeedRun { param($Tenants, $Round) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Push-AuditLogFeedProcessV3.ps1')
    function New-Window([string]$Tenant, [int]$Records = 5) {
        [pscustomobject]@{ TenantFilter = $Tenant; SearchId = 'feed-20261017000000'; WindowRowKey = 'FEED-20261017000000'; RecordCount = $Records }
    }
}

Describe 'Push-AuditLogFeedProcessV3' {
    BeforeEach {
        $script:Started = [System.Collections.Generic.List[object]]::new()
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject) }
        Mock New-CippQueueEntry { [pscustomobject]@{ RowKey = 'queue-1' } }
    }

    It 'queues every stored window in one uncapped run under one queue entry' {
        Push-AuditLogFeedProcessV3 -Item ([pscustomobject]@{ Results = @((New-Window 'contoso.com' -Records 7), (New-Window 'fabrikam.com')) })
        $script:Started | Should -HaveCount 1
        $Run = $script:Started[0]
        $Run.OrchestratorName | Should -Be 'AuditLogProcessV3'
        $Run.PSObject.Properties.Name | Should -Not -Contain 'MaxConcurrency'
        $Run.Batch.TenantFilter | Should -Be @('contoso.com', 'fabrikam.com')
        $Run.Batch[0].FunctionName | Should -Be 'AuditLogTenantProcessV2'
        $Run.Batch[0].SearchId | Should -Be 'feed-20261017000000'
        $Run.Batch[0].WindowRowKey | Should -Be 'FEED-20261017000000'
        $Run.Batch[0].RecordCount | Should -Be 7
        @($Run.Batch.QueueId | Select-Object -Unique) | Should -Be @('queue-1')
        Should -Invoke New-CippQueueEntry -Times 1 -Exactly -ParameterFilter { $TotalTasks -eq 2 }
    }

    It 'queues a window returned twice once' {
        Push-AuditLogFeedProcessV3 -Item ([pscustomobject]@{ Results = @((New-Window 'contoso.com'), (New-Window 'CONTOSO.com')) })
        $script:Started[0].Batch | Should -HaveCount 1
    }

    It 'queues nothing when no window was stored' {
        Push-AuditLogFeedProcessV3 -Item ([pscustomobject]@{ Results = @([pscustomobject]@{ TenantFilter = 'contoso.com' }) })
        $script:Started | Should -HaveCount 0
        Should -Invoke New-CippQueueEntry -Times 0 -Exactly
    }

    It 'names the run after the caller when asked' {
        Push-AuditLogFeedProcessV3 -Item ([pscustomobject]@{ Results = @(New-Window 'contoso.com'); Parameters = @{ RunName = 'AuditLogSweepV3' } })
        $script:Started[0].OrchestratorName | Should -Be 'AuditLogSweepV3'
    }
}

Describe 'Push-AuditLogFeedProcessV3 after a feed round' {
    BeforeEach {
        $script:Started = [System.Collections.Generic.List[object]]::new()
        $script:RoundStart = [datetime]::UtcNow.AddMinutes(-25)
        $script:LedgerRows = @()
        $script:CursorRows = @()
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject) }
        Mock New-CippQueueEntry { [pscustomobject]@{ RowKey = 'queue-1' } }
        Mock Get-CIPPAzDataTableEntity { if ($TableName -eq 'AuditLogCoverage') { $script:LedgerRows } else { $script:CursorRows } }
        Mock Get-CIPPAuditLogTenantScope { foreach ($T in 'stopped.com', 'finished.com', 'stuck.com') { [pscustomobject]@{ defaultDomainName = $T; customerId = "id-$T"; ContentTypes = @('Audit.Exchange') } } }
        Mock Start-CIPPAuditLogFeedRun { 1 }
        Mock Write-LogMessage {}
    }

    It 'also processes the windows its stopped tasks left Storing' {
        $script:LedgerRows = @([pscustomobject]@{ PartitionKey = 'stopped.com'; RowKey = 'FEED-2'; SearchId = 'feed-2'; CandidateCount = 3 })
        Push-AuditLogFeedProcessV3 -Item ([pscustomobject]@{ Results = @(New-Window 'contoso.com'); Parameters = @{ CycleId = '20261024034500'; RoundStartUtc = $script:RoundStart.ToString('o'); Round = 0 } })
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'AuditLogCoverage' -and $Filter -like "*State eq 'Storing'*CycleId eq '20261024034500'*" }
        $script:Started[0].Batch.TenantFilter | Should -Be @('contoso.com', 'stopped.com')
        $script:Started[0].Batch[1].RecordCount | Should -Be 3
    }

    It 'runs again only the tenants that saved a checkpoint this round without finishing' {
        $script:CursorRows = @(
            [pscustomobject]@{ PartitionKey = 'stopped.com'; RowKey = 'Audit.Exchange'; CheckpointUtc = [datetime]::UtcNow.AddMinutes(-5); LastPolledUtc = $script:RoundStart.AddHours(-1) }
            [pscustomobject]@{ PartitionKey = 'finished.com'; RowKey = 'Audit.Exchange'; CheckpointUtc = [datetime]::UtcNow.AddMinutes(-5); LastPolledUtc = $script:RoundStart.AddMinutes(1) }
            [pscustomobject]@{ PartitionKey = 'stuck.com'; RowKey = 'Audit.Exchange'; CheckpointUtc = $script:RoundStart.AddHours(-1); LastPolledUtc = $script:RoundStart.AddHours(-1) }
        )
        Push-AuditLogFeedProcessV3 -Item ([pscustomobject]@{ Results = @(); Parameters = @{ CycleId = '20261024034500'; RoundStartUtc = $script:RoundStart.ToString('o'); Round = 2 } })
        Should -Invoke Start-CIPPAuditLogFeedRun -Times 1 -Exactly -ParameterFilter { @($Tenants.defaultDomainName) -join ',' -eq 'stopped.com' -and $Round -eq 3 }
    }

    It 'starts no round when nothing checkpointed, and none after a sweep' {
        $script:CursorRows = @([pscustomobject]@{ PartitionKey = 'stuck.com'; RowKey = 'Audit.Exchange'; LastPolledUtc = $script:RoundStart.AddHours(-1) })
        Push-AuditLogFeedProcessV3 -Item ([pscustomobject]@{ Results = @(); Parameters = @{ CycleId = '20261024034500'; RoundStartUtc = $script:RoundStart.ToString('o'); Round = 0 } })
        Push-AuditLogFeedProcessV3 -Item ([pscustomobject]@{ Results = @(New-Window 'contoso.com'); Parameters = @{ RunName = 'AuditLogSweepV3' } })
        Should -Invoke Start-CIPPAuditLogFeedRun -Times 0 -Exactly
    }
}
