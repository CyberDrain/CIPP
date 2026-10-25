# Pester tests for Invoke-ListAuditLogRuleMatches - which of the alerts set up now would fire on a saved alert's record.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    $FunctionPath = (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Invoke-ListAuditLogRuleMatches.ps1' -File)[0].FullName

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CippTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property) }
    function ConvertTo-CIPPODataFilterValue { param($Value, $Type) $Value }
    function Get-CippErrorStatusCode { param($ErrorRecord) if ($ErrorRecord.Exception -is [System.Management.Automation.ItemNotFoundException]) { 404 } else { 500 } }
    function Test-CIPPAuditLogRules { param($TenantFilter, $Rows, [switch]$EvaluateOnly, [switch]$AllMatches) }
    function Get-CIPPAuditLogRuleSet { param($TenantFilter) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Split-CIPPAuditLogConditions.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Get-CIPPAuditLogRuleAnchor.ps1')
    . $FunctionPath

    function Invoke-Check([string]$LogId = 'log-1') {
        Invoke-ListAuditLogRuleMatches -Request ([pscustomobject]@{ Query = [pscustomobject]@{ tenantFilter = 'contoso.com'; LogId = $LogId } }) -TriggerMetadata $null
    }
    function New-Rule([string]$Key, [string]$Comment, [object[]]$Conditions, [string]$Threshold, $Excluded) {
        [pscustomobject]@{ RowKey = $Key; AlertComment = $Comment; LogType = 'Audit.Exchange'; Threshold = $Threshold; Excluded = $Excluded
            Conditions = ConvertTo-Json -Compress -Depth 5 -InputObject @($Conditions) }
    }
    $script:OpCondition = @{ Property = @{ label = 'Operation'; value = 'List:Operation' }; Operator = @{ value = 'in'; label = 'In' }; Input = @(@{ value = 'New-InboxRule' }, @{ value = 'Set-InboxRule' }) }
}

Describe 'Invoke-ListAuditLogRuleMatches' {
    BeforeEach {
        $Record = [ordered]@{ Id = 'r1'; Operation = 'New-InboxRule'; UserId = 'bob@contoso.com'; CreationTime = '2026-10-24T10:00:00'; ForwardTo = 'evil@x.com' }
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ Data = ConvertTo-Json -Depth 6 -Compress -InputObject @{ RawData = @{ AuditRecord = (ConvertTo-Json -Compress -InputObject $Record) } } }
        }
        Mock Get-CIPPAuditLogRuleSet {
            New-Rule 'first' 'First match' @($script:OpCondition)
            New-Rule 'second' 'Also matches' @($script:OpCondition)
            New-Rule 'forward' 'Redirects only' @($script:OpCondition)
            New-Rule 'other' 'Other operations' @(@{ Property = @{ label = 'Operation' }; Operator = @{ value = 'eq' }; Input = @{ value = 'Set-Mailbox' } })
            New-Rule 'count' 'Mass inbox rules' @($script:OpCondition) '{"Count":10,"Minutes":20}'
            New-Rule 'excluded' 'Excluded here' @($script:OpCondition) $null @(@{ value = 'contoso.com' })
            New-Rule 'broken' 'No anchor' @(@{ Property = @{ label = 'UserId' }; Operator = @{ value = 'like' }; Input = @{ value = '*' } })
        }
        # The engine's report: rules in order, each condition on its own.
        Mock Test-CIPPAuditLogRules {
            [pscustomobject]@{
                Error       = $null
                RuleReports = @([pscustomobject]@{
                        Record  = $Rows[0]
                        Clauses = @(
                            [pscustomobject]@{ RuleKey = 'first'; Group = 0; Anchored = $true; Matched = $true; Conditions = @([pscustomobject]@{ Condition = 'Operation is In'; Passed = $true }) }
                            [pscustomobject]@{ RuleKey = 'second'; Group = 0; Anchored = $true; Matched = $true; Conditions = @([pscustomobject]@{ Condition = 'Operation is In'; Passed = $true }) }
                            [pscustomobject]@{ RuleKey = 'forward'; Group = 0; Anchored = $true; Matched = $false; Conditions = @([pscustomobject]@{ Condition = 'Operation is In'; Passed = $true }, [pscustomobject]@{ Condition = 'RedirectTo is Like *@*'; Passed = $false }) }
                            [pscustomobject]@{ RuleKey = 'other'; Group = 0; Anchored = $false; Matched = $false; Conditions = @([pscustomobject]@{ Condition = 'Operation is Equals to Set-Mailbox'; Passed = $false }) }
                        )
                    })
            }
        }
    }

    It 'checks the saved record without sending anything, and reports each alert in plain language' {
        $Response = Invoke-Check
        $Response.StatusCode | Should -Be 200
        Should -Invoke Test-CIPPAuditLogRules -Times 1 -Exactly -ParameterFilter { $EvaluateOnly -and $AllMatches -and $Rows[0].Operation -eq 'New-InboxRule' }
        $Rows = @{}
        foreach ($Row in $Response.Body.Results) { $Rows[$Row.Alert] = $Row }
        $Rows['First match'].WouldAlert | Should -Be 'Sent'
        $Rows['Also matches'].WouldAlert | Should -Be 'Matches, another alert is sent first'
        $Rows['Redirects only'].WouldAlert | Should -Be 'No'
        $Rows['Redirects only'].Reason | Should -BeLike '*Not met: RedirectTo is Like `*@`*.'
        $Rows['Other operations'].Reason | Should -Be "The alert looks for other operations, not 'New-InboxRule'."
        $Rows['Mass inbox rules'].Conditions | Should -HaveCount 0
        $Rows['Mass inbox rules'].WouldAlert | Should -Be 'Counts toward it'
        $Rows['Mass inbox rules'].Reason | Should -BeLike '*10 times within 20 minutes*'
        $Rows['Excluded here'].Reason | Should -Be 'This tenant is excluded from the alert.'
        $Rows['No anchor'].Reason | Should -BeLike '*needs an Operation condition*'
        $Response.Body.Results[0].Alert | Should -Be 'First match'
        $Response.Body.Metadata.Operation | Should -Be 'New-InboxRule'
    }

    It 'returns 404 for a saved alert that does not exist' {
        Mock Get-CIPPAzDataTableEntity {}
        (Invoke-Check -LogId 'missing').StatusCode | Should -Be 404
    }

    It 'returns 400 without a LogId' {
        (Invoke-ListAuditLogRuleMatches -Request ([pscustomobject]@{ Query = [pscustomobject]@{ tenantFilter = 'contoso.com' } }) -TriggerMetadata $null).StatusCode | Should -Be 400
    }
}
