# Pester tests for the audit log feed timer: tenant scope, cursor backoff, the missed-window sweep and Graph search ingestion.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Public = Join-Path $RepoRoot 'Modules/CIPPCore/Public'

    function Get-CippTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force, $OperationType) }
    function Expand-CIPPTenantGroups { param($TenantFilter) }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function Start-CIPPOrchestrator { param($InputObject) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }
    function Start-AuditLogSearchCreationV2 {}
    function Start-AuditLogIngestionV2 {}
    function Push-AuditLogFeedProcessV3 { param($Item) }

    function New-Rule([object[]]$Tenants, [object[]]$Excluded, [string]$Type) {
        [pscustomobject]@{
            PartitionKey = 'Webhookv2'; Disabled = $false; Type = $Type
            Tenants = ConvertTo-Json -InputObject @($Tenants) -Compress
            excludedTenants = if ($Excluded) { ConvertTo-Json -InputObject @($Excluded) -Compress }
        }
    }

    # The same stand-in for Craft's bridge as the scheduler tests, so either file can load it first.
    if (-not ('Craft.Services.OrchestratorBridge' -as [type])) {
        Add-Type -TypeDefinition @'
namespace Craft.Services {
    public static class OrchestratorBridge {
        public static System.Collections.Generic.List<object[]> Calls = new System.Collections.Generic.List<object[]>();
        public static System.Collections.Generic.HashSet<string> ActiveNames = new System.Collections.Generic.HashSet<string>();
        public static bool IsRunActive(string name) { return ActiveNames.Contains(name); }
        public static void QueueOrchestrationFromFile(string name, string batchFilePath, int priority,
            string postExecFunctionName, string postExecParametersJson, string reference, string parentRunName,
            bool sequential, bool allowCollision, int maxConcurrency, bool stopOnFailure) {
            Calls.Add(new object[] { name, parentRunName, allowCollision, priority, sequential, maxConcurrency, stopOnFailure });
            System.IO.File.Delete(batchFilePath);
        }
    }
}
'@
    }

    . (Join-Path $Public 'AuditLogs/Get-CIPPAuditLogTenantScope.ps1')
    . (Join-Path $Public 'Entrypoints/Orchestrator Functions/Start-AuditLogFeedV3.ps1')
}

Describe 'Get-CIPPAuditLogTenantScope' {
    BeforeEach {
        Mock Expand-CIPPTenantGroups { foreach ($T in $TenantFilter) { [pscustomobject]@{ value = $T.value } } }
        Mock Get-Tenants {
            [pscustomobject]@{ defaultDomainName = 'contoso.com'; customerId = 'tid-1' }
            [pscustomobject]@{ defaultDomainName = 'fabrikam.com'; customerId = 'tid-2' }
            [pscustomobject]@{ defaultDomainName = 'off.com'; customerId = 'tid-3' }
        }
        $script:Rules = @()
        $script:Disabled = @([pscustomobject]@{ RowKey = 'off.com'; ExpiresAtUnix = [datetimeoffset]::UtcNow.AddHours(1).ToUnixTimeSeconds() })
        Mock Get-CIPPAzDataTableEntity { if ($TableName -eq 'WebhookRules') { $script:Rules } else { $script:Disabled } }
    }

    It 'unions the content types of every rule covering a tenant' {
        $script:Rules = @((New-Rule -Tenants @(@{ value = 'contoso.com' }) -Type 'Audit.Exchange'), (New-Rule -Tenants @(@{ value = 'AllTenants' }) -Type 'Audit.AzureActiveDirectory'))
        $Scope = @(Get-CIPPAuditLogTenantScope)
        ($Scope.Where({ $_.defaultDomainName -eq 'contoso.com' }))[0].ContentTypes | Sort-Object | Should -Be @('Audit.AzureActiveDirectory', 'Audit.Exchange')
        ($Scope.Where({ $_.defaultDomainName -eq 'fabrikam.com' }))[0].ContentTypes | Should -Be @('Audit.AzureActiveDirectory')
    }

    It 'treats a rule without a type as both content types' {
        $script:Rules = @(New-Rule -Tenants @(@{ value = 'contoso.com' }))
        (@(Get-CIPPAuditLogTenantScope)[0].ContentTypes | Sort-Object) | Should -Be @('Audit.AzureActiveDirectory', 'Audit.Exchange')
    }

    It 'leaves out excluded and auditing-disabled tenants' {
        $script:Rules = @(New-Rule -Tenants @(@{ value = 'AllTenants' }) -Excluded @(@{ value = 'fabrikam.com' }) -Type 'Audit.Exchange')
        @(Get-CIPPAuditLogTenantScope).defaultDomainName | Should -Be @('contoso.com')
    }
}

Describe 'Start-AuditLogFeedV3' {
    BeforeEach {
        $script:Started = [System.Collections.Generic.List[object]]::new()
        $script:CursorRows = @()
        $script:LedgerRows = @()
        Mock Get-CIPPAuditLogTenantScope { [pscustomobject]@{ defaultDomainName = 'contoso.com'; customerId = 'tid-1'; ContentTypes = @('Audit.AzureActiveDirectory', 'Audit.Exchange') } }
        Mock Get-CIPPAzDataTableEntity { if ($TableName -eq 'AuditLogCoverage') { $script:LedgerRows } else { $script:CursorRows } }
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject) }
        Mock Push-AuditLogFeedProcessV3 {}
        Mock Start-AuditLogIngestionV2 {}
        Mock Start-AuditLogSearchCreationV2 {}
        Mock Write-LogMessage {}
        [Craft.Services.OrchestratorBridge]::ActiveNames.Clear()
    }

    It 'skips the feed while a processing run is active, but still sweeps and ingests' {
        [void][Craft.Services.OrchestratorBridge]::ActiveNames.Add('AuditLogProcessV3')
        Start-AuditLogFeedV3
        $script:Started | Should -HaveCount 0
        Should -Invoke Get-CIPPAuditLogTenantScope -Times 0 -Exactly
        Should -Invoke Get-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $TableName -eq 'AuditLogCoverage' }
        Should -Invoke Start-AuditLogIngestionV2 -Times 1 -Exactly
    }

    It 'leaves out a content type in backoff and passes the other cursor along' {
        $script:CursorRows = @(
            [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'Audit.Exchange'; NextAttemptUtc = [datetime]::UtcNow.AddHours(1) }
            [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = 'Audit.AzureActiveDirectory'; LastEndUtc = [datetime]'2026-10-17T05:00:00Z'; Attempts = 0 }
        )
        Start-AuditLogFeedV3
        $Tenant = $script:Started[0].Batch[0].Tenants[0]
        $Tenant.ContentTypes | Should -Be @('Audit.AzureActiveDirectory')
        $Tenant.Cursors['Audit.AzureActiveDirectory'].LastEndUtc | Should -Be ([datetime]'2026-10-17T05:00:00Z')
    }

    It 'skips a tenant with every content type in backoff' {
        $script:CursorRows = foreach ($Ct in 'Audit.Exchange', 'Audit.AzureActiveDirectory') { [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = $Ct; NextAttemptUtc = [datetime]::UtcNow.AddHours(1) } }
        Start-AuditLogFeedV3
        $script:Started | Should -HaveCount 0
    }

    It 'queues one feed run at a time, processed by its post-execution' {
        Start-AuditLogFeedV3
        $script:Started[0].OrchestratorName | Should -Be 'AuditLogFeedV3'
        $script:Started[0].AllowCollision | Should -BeFalse
        $script:Started[0].PostExecution.FunctionName | Should -Be 'AuditLogFeedProcessV3'
    }

    It 'sweeps windows older than 5 minutes once no feed, processing or sweep run is active' {
        $Now = [datetimeoffset]::UtcNow
        $script:LedgerRows = @(
            [pscustomobject]@{ PartitionKey = 'failed.com'; RowKey = 'FEED-1'; SearchId = 'feed-1'; CandidateCount = 9; State = 'Downloaded'; Timestamp = $Now.AddMinutes(-6) }
            [pscustomobject]@{ PartitionKey = 'lost.com'; RowKey = 'FEED-2'; SearchId = 'feed-2'; CandidateCount = 4; State = 'Processing'; Timestamp = $Now.AddMinutes(-6) }
            [pscustomobject]@{ PartitionKey = 'fresh.com'; RowKey = 'FEED-3'; SearchId = 'feed-3'; CandidateCount = 1; State = 'Processing'; Timestamp = $Now.AddMinutes(-2) }
            [pscustomobject]@{ PartitionKey = 'crashed.com'; RowKey = 'FEED-4'; SearchId = 'feed-4'; State = 'Storing'; Timestamp = $Now.AddMinutes(-6) }
        )
        Start-AuditLogFeedV3
        Should -Invoke Push-AuditLogFeedProcessV3 -Times 1 -Exactly -ParameterFilter {
            $Lost = @($Item.Results).Where({ $_.TenantFilter -eq 'lost.com' })[0]
            (@($Item.Results.TenantFilter) | Sort-Object) -join ',' -eq 'crashed.com,failed.com,lost.com' -and $Item.Parameters.RunName -eq 'AuditLogSweepV3' -and
            $Lost.WindowRowKey -eq 'FEED-2' -and $Lost.SearchId -eq 'feed-2' -and $Lost.RecordCount -eq 4
        }
    }

    It 'leaves windows to an active run unless they have been Processing for over 2 hours' {
        $Now = [datetimeoffset]::UtcNow
        $script:LedgerRows = @(
            [pscustomobject]@{ PartitionKey = 'waiting.com'; RowKey = 'FEED-1'; SearchId = 'feed-1'; State = 'Processing'; Timestamp = $Now.AddMinutes(-40) }
            [pscustomobject]@{ PartitionKey = 'queued.com'; RowKey = 'FEED-2'; SearchId = 'feed-2'; State = 'Downloaded'; Timestamp = $Now.AddMinutes(-40) }
            [pscustomobject]@{ PartitionKey = 'stuck.com'; RowKey = 'FEED-3'; SearchId = 'feed-3'; State = 'Processing'; Timestamp = $Now.AddHours(-3) }
        )
        foreach ($Run in 'AuditLogFeedV3', 'AuditLogProcessV3', 'AuditLogSweepV3') {
            [Craft.Services.OrchestratorBridge]::ActiveNames.Clear()
            [void][Craft.Services.OrchestratorBridge]::ActiveNames.Add($Run)
            Start-AuditLogFeedV3
        }
        Should -Invoke Push-AuditLogFeedProcessV3 -Times 3 -Exactly -ParameterFilter { @($Item.Results.TenantFilter) -join ',' -eq 'stuck.com' }
    }

    It 'still polls the feed while only a sweep run is active' {
        [void][Craft.Services.OrchestratorBridge]::ActiveNames.Add('AuditLogSweepV3')
        Start-AuditLogFeedV3
        $script:Started[0].OrchestratorName | Should -Be 'AuditLogFeedV3'
    }

    It 'still downloads created Graph searches when the feed stage fails' {
        Mock Get-CIPPAuditLogTenantScope { throw 'rules unavailable' }
        Start-AuditLogFeedV3
        Should -Invoke Start-AuditLogIngestionV2 -Times 1 -Exactly
    }

    It 'never creates scheduled Graph searches' {
        Start-AuditLogFeedV3
        Should -Invoke Start-AuditLogSearchCreationV2 -Times 0 -Exactly
    }
}
