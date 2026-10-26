function Start-AuditLogFeedV3 {
    <#
    .SYNOPSIS
        Timer entrypoint for audit log alerting: the Management Activity API feed, plus Graph audit searches already
        created.
    .DESCRIPTION
        Each tick runs two independent stages:
          1. Feed: while a cycle is still going (the AuditLogFeedListV3 run, or an AuditLogFeedBlobsV3 run of its family)
             the tick leaves it be; the cursors carry on from where it stops. Otherwise Start-CIPPAuditLogFeedListRun
             lists every in-scope tenant with a content type due, in tasks of 50 tenants, and its post-execution fans
             the blobs out to bounded runs of batch tasks that download them and send their alerts.
          2. Graph searches: Start-AuditLogIngestionV2 downloads and processes searches that already exist, which are
             manual searches and scheduled windows created before the feed. No scheduled searches are created.
        Both stages run only while the Audit Log Feed feature is enabled; otherwise Start-AuditLogPlannerV2 creates and
        processes Graph searches. Either way, once a day it raises an alert for each enabled rule without an anchor, which
        the engine skips.
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    # The host scheduler fires every CIPPTimers.json entry regardless of feature flags, so the feed gates itself.
    $FeedFlag = $(try { Get-CIPPFeatureFlag -Id 'AuditLogFeed' } catch { $null })
    if ($FeedFlag.Enabled -ne $true) {
        Write-Information 'AuditLogFeedV3: skipped, the Audit Log Feed feature is disabled and Graph searches collect audit logs'
    } else {
        $Bridge = 'Craft.Services.OrchestratorBridge' -as [type]
        if ($Bridge -and ([Craft.Services.OrchestratorBridge]::IsRunActive('AuditLogFeedListV3') -or [Craft.Services.OrchestratorBridge]::IsRunActive('AuditLogFeedBlobsV3'))) {
            Write-Information 'AuditLogFeedV3: a feed cycle is still going'
        } else {
            try {
                if ($PSCmdlet.ShouldProcess('Start-AuditLogFeedV3', 'Poll the audit log feed')) {
                    $Queued = Start-CIPPAuditLogFeedListRun -Tenants @(Get-CIPPAuditLogTenantScope)
                    Write-Information "AuditLogFeedV3: $Queued listing task(s) queued"
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
                $Groups = @(Split-CIPPAuditLogConditions -Conditions $Conditions)
                if ($Groups.Count -gt 0 -and $Groups.Where({ $null -eq (Get-CIPPAuditLogRuleAnchor -Conditions $_.Conditions) }, 'First').Count -eq 0) { continue }
                $Name = if ($Rule.AlertComment) { "'$($Rule.AlertComment)'" } else { $Rule.RowKey }
                Write-LogMessage -API 'AuditLogFeedV3' -message "Audit log alert $Name is skipped: each group of its conditions needs an Operation condition using Equals, In, or Like with at least three characters of text. Edit the alert to add one." -sev Alert
            }
            Add-CIPPAzDataTableEntity @ConfigTable -Entity @{ PartitionKey = 'AuditLogRuleAnchorCheck'; RowKey = 'AuditLogRuleAnchorCheck'; Date = $Today } -Force
        }
    } catch {
        Write-Information "AuditLogFeedV3: could not check the audit log rules for anchors: $($_.Exception.Message)"
    }
}
