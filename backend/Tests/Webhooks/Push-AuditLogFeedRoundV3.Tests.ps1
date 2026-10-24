# Pester tests for Push-AuditLogFeedRoundV3 - the feed run's post-execution, which runs again the tenants that stopped part way.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CippTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property) }
    function Get-CIPPAuditLogTenantScope {}
    function Start-CIPPAuditLogFeedRun { param($Tenants, $Round) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Push-AuditLogFeedRoundV3.ps1')
    function Invoke-Round([int]$Round = 0) { Push-AuditLogFeedRoundV3 -Item ([pscustomobject]@{ Results = @(); Parameters = @{ RoundStartUtc = $script:RoundStart.ToString('o'); Round = $Round } }) }
}

Describe 'Push-AuditLogFeedRoundV3' {
    BeforeEach {
        $script:RoundStart = [datetime]::UtcNow.AddMinutes(-25)
        $script:CursorRows = @()
        Mock Get-CIPPAzDataTableEntity { $script:CursorRows }
        Mock Get-CIPPAuditLogTenantScope { foreach ($T in 'stopped.com', 'finished.com', 'stuck.com') { [pscustomobject]@{ defaultDomainName = $T; customerId = "id-$T"; ContentTypes = @('Audit.Exchange') } } }
        Mock Start-CIPPAuditLogFeedRun { 1 }
        Mock Write-LogMessage {}
    }

    It 'runs again only the tenants that saved a checkpoint this round without finishing, as the next round' {
        $script:CursorRows = @(
            [pscustomobject]@{ PartitionKey = 'stopped.com'; RowKey = 'Audit.Exchange'; CheckpointUtc = [datetime]::UtcNow.AddMinutes(-5); LastPolledUtc = $script:RoundStart.AddHours(-1) }
            [pscustomobject]@{ PartitionKey = 'finished.com'; RowKey = 'Audit.Exchange'; CheckpointUtc = [datetime]::UtcNow.AddMinutes(-5); LastPolledUtc = $script:RoundStart.AddMinutes(1) }
            [pscustomobject]@{ PartitionKey = 'stuck.com'; RowKey = 'Audit.Exchange'; CheckpointUtc = $script:RoundStart.AddHours(-1); LastPolledUtc = $script:RoundStart.AddHours(-1) }
        )
        Invoke-Round -Round 2
        Should -Invoke Start-CIPPAuditLogFeedRun -Times 1 -Exactly -ParameterFilter { @($Tenants.defaultDomainName) -join ',' -eq 'stopped.com' -and $Round -eq 3 }
    }

    It 'starts no round when nothing checkpointed during this one' {
        $script:CursorRows = @([pscustomobject]@{ PartitionKey = 'stuck.com'; RowKey = 'Audit.Exchange'; LastPolledUtc = $script:RoundStart.AddHours(-1) })
        Invoke-Round
        Should -Invoke Start-CIPPAuditLogFeedRun -Times 0 -Exactly
    }

    It 'does nothing without a round start' {
        Push-AuditLogFeedRoundV3 -Item ([pscustomobject]@{ Results = @(); Parameters = @{} })
        Should -Invoke Get-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'logs and leaves the cursors to the next tick when the round cannot be queued' {
        $script:CursorRows = @([pscustomobject]@{ PartitionKey = 'stopped.com'; RowKey = 'Audit.Exchange'; CheckpointUtc = [datetime]::UtcNow; LastPolledUtc = $script:RoundStart.AddHours(-1) })
        Mock Start-CIPPAuditLogFeedRun { throw 'queue unavailable' }
        Invoke-Round
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Error' }
    }
}
