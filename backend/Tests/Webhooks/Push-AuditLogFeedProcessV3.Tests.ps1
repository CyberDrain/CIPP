# Pester tests for Push-AuditLogFeedProcessV3 - the feed run's post-execution.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function New-CippQueueEntry { param($Name, $Reference, $TotalTasks) }
    function Start-CIPPOrchestrator { param($InputObject) }
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
