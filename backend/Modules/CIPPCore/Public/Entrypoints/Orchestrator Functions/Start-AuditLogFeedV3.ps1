function Start-AuditLogFeedV3 {
    <#
    .SYNOPSIS
        Timer entrypoint for audit log alerting: the Management Activity API feed, plus Graph audit searches already
        created.
    .DESCRIPTION
        Each tick runs two independent stages:
          1. Feed: while a feed round is still going (AuditLogFeedV3 or a later AuditLogFeedV3-<guid> round) the tick
             leaves it be; the cursors carry the range to the round. Otherwise Start-CIPPAuditLogFeedRun queues one
             AuditLogFeedV3 task per in-scope tenant with a content type due. Each task reads its feed and sends its alerts
             itself, and the run's post-execution runs again the tenants that checkpointed but did not finish.
          2. Graph searches: Start-AuditLogIngestionV2 downloads and processes searches that already exist, which are
             manual searches and scheduled windows created before the feed. No scheduled searches are created.
        Once a day it also raises an alert for each enabled rule without an anchor, which the engine skips.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $Bridge = 'Craft.Services.OrchestratorBridge' -as [type]
    if ($Bridge -and [Craft.Services.OrchestratorBridge]::IsRunActive('AuditLogFeedV3')) {
        Write-Information 'AuditLogFeedV3: a feed round is still running'
    } else {
        try {
            if ($PSCmdlet.ShouldProcess('Start-AuditLogFeedV3', 'Poll the audit log feed')) {
                $Queued = Start-CIPPAuditLogFeedRun -Tenants @(Get-CIPPAuditLogTenantScope)
                Write-Information "AuditLogFeedV3: $Queued tenant task(s) queued"
            }
        } catch {
            Write-LogMessage -API 'AuditLogFeedV3' -message 'Audit log feed stage failed' -sev Error -LogData (Get-CippException -Exception $_)
        }
    }

    try {
        Start-AuditLogIngestionV2
    } catch {
        Write-LogMessage -API 'AuditLogFeedV3' -message 'Audit log search ingestion failed' -sev Error -LogData (Get-CippException -Exception $_)
    }

    # Once a day, an alert for each enabled rule the engine skips for want of an anchor (Get-CIPPAuditLogRuleAnchor).
    try {
        $ConfigTable = Get-CIPPTable -TableName 'Config'
        $Today = [datetime]::UtcNow.ToString('yyyy-MM-dd')
        $Checked = Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'AuditLogRuleAnchorCheck' and RowKey eq 'AuditLogRuleAnchorCheck'"
        if ($Checked.Date -ne $Today) {
            $RuleTable = Get-CIPPTable -TableName 'WebhookRules'
            foreach ($Rule in (Get-CIPPAzDataTableEntity @RuleTable)) {
                if ($Rule.Disabled -eq $true -or [string]::IsNullOrEmpty($Rule.Tenants)) { continue }
                $Conditions = $Rule.Conditions | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($null -ne (Get-CIPPAuditLogRuleAnchor -Conditions $Conditions)) { continue }
                $Name = if ($Rule.AlertComment) { "'$($Rule.AlertComment)'" } else { $Rule.RowKey }
                Write-LogMessage -API 'AuditLogFeedV3' -message "Audit log alert $Name is skipped: it needs an Operation condition using Equals, In, or Like with at least three characters of text. Edit the alert to add one." -sev Alert
            }
            Add-CIPPAzDataTableEntity @ConfigTable -Entity @{ PartitionKey = 'AuditLogRuleAnchorCheck'; RowKey = 'AuditLogRuleAnchorCheck'; Date = $Today } -Force
        }
    } catch {
        Write-Information "AuditLogFeedV3: could not check the audit log rules for anchors: $($_.Exception.Message)"
    }
}
