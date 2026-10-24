# Pester tests for the audit log feed timer: tenant scope, cursor backoff, feed rounds and Graph search ingestion.

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
    . (Join-Path $Public 'Webhooks/Start-CIPPAuditLogFeedRun.ps1')
    . (Join-Path $Public 'Webhooks/Get-CIPPAuditLogRuleAnchor.ps1')
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
        Mock Get-CIPPAuditLogTenantScope { [pscustomobject]@{ defaultDomainName = 'contoso.com'; customerId = 'tid-1'; ContentTypes = @('Audit.AzureActiveDirectory', 'Audit.Exchange') } }
        Mock Get-CIPPAzDataTableEntity { $script:CursorRows }
        Mock Start-CIPPOrchestrator { $script:Started.Add($InputObject) }
        Mock Start-AuditLogIngestionV2 {}
        Mock Start-AuditLogSearchCreationV2 {}
        Mock Write-LogMessage {}
        [Craft.Services.OrchestratorBridge]::ActiveNames.Clear()
    }

    It 'leaves a feed round that is still running be, but still ingests Graph searches' {
        [void][Craft.Services.OrchestratorBridge]::ActiveNames.Add('AuditLogFeedV3')
        Start-AuditLogFeedV3
        $script:Started | Should -HaveCount 0
        Should -Invoke Get-CIPPAuditLogTenantScope -Times 0 -Exactly
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
        $script:Started[0].PostExecution.FunctionName | Should -Be 'AuditLogFeedRoundV3'
    }

    It 'queues one task per tenant in an uncapped run, as round 0 with its start for the post-execution' {
        Mock Get-CIPPAuditLogTenantScope { foreach ($n in 1..3) { [pscustomobject]@{ defaultDomainName = "t$n.com"; customerId = "tid-$n"; ContentTypes = @('Audit.Exchange') } } }
        Start-AuditLogFeedV3
        $Run = $script:Started[0]
        $Run.Batch | Should -HaveCount 3
        @($Run.Batch.ForEach({ @($_.Tenants).Count })) | Should -Be @(1, 1, 1)
        $Run.Batch.Tenants.TenantFilter | Should -Be @('t1.com', 't2.com', 't3.com')
        $Run.PSObject.Properties.Name | Should -Not -Contain 'MaxConcurrency'
        $Run.PostExecution.Parameters.Round | Should -Be 0
        ([datetimeoffset]$Run.PostExecution.Parameters.RoundStartUtc).UtcDateTime | Should -BeLessOrEqual ([datetime]::UtcNow)
    }

    It 'names a later round into the same run family and lets it start while its own round finishes' {
        $null = Start-CIPPAuditLogFeedRun -Tenants @([pscustomobject]@{ defaultDomainName = 'contoso.com'; customerId = 'tid-1'; ContentTypes = @('Audit.Exchange') }) -Round 2
        $script:Started[0].OrchestratorName | Should -Match '^AuditLogFeedV3-[0-9a-f-]{36}$'
        $script:Started[0].AllowCollision | Should -BeTrue
        $script:Started[0].PostExecution.Parameters.Round | Should -Be 2
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

Describe 'Start-AuditLogFeedV3 unanchored rule check' {
    BeforeEach {
        [Craft.Services.OrchestratorBridge]::ActiveNames.Clear()
        [void][Craft.Services.OrchestratorBridge]::ActiveNames.Add('AuditLogFeedV3')
        $script:CheckRow = $null
        $Operation = '[{"Property":{"label":"Operation"},"Operator":{"value":"eq"},"Input":{"value":"New-InboxRule"}}]'
        $UserOnly = '[{"Property":{"label":"UserId"},"Operator":{"value":"like"},"Input":{"value":"ServicePrincipal_*"}}]'
        $script:RuleRows = @(
            [pscustomobject]@{ RowKey = 'anchored'; Tenants = '[{"value":"AllTenants"}]'; Conditions = $Operation; AlertComment = 'Inbox rules' }
            [pscustomobject]@{ RowKey = 'unanchored'; Tenants = '[{"value":"AllTenants"}]'; Conditions = $UserOnly; AlertComment = 'App actors' }
            [pscustomobject]@{ RowKey = 'disabled'; Tenants = '[{"value":"AllTenants"}]'; Conditions = $UserOnly; Disabled = $true }
        )
        Mock Get-CIPPAzDataTableEntity { if ($TableName -eq 'WebhookRules') { $script:RuleRows } elseif ($TableName -eq 'Config') { $script:CheckRow } }
        Mock Add-CIPPAzDataTableEntity { if ($TableName -eq 'Config') { $script:CheckRow = [pscustomobject]$Entity } }
        Mock Start-AuditLogIngestionV2 {}
        Mock Write-LogMessage {}
    }

    It 'raises one alert a day for each enabled rule without an anchor' {
        Start-AuditLogFeedV3
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Alert' }
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Alert' -and $message -like "*'App actors' is skipped*" }
        Start-AuditLogFeedV3
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $sev -eq 'Alert' }
    }
}
