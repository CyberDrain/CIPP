function Invoke-ListAuditLogRuleMatches {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.Alert.Read
    .SYNOPSIS
        Checks a saved audit log alert against the audit log alerts set up now, and says which of them would fire.
    .DESCRIPTION
        Takes the audit record a saved alert (Saved Logs) was sent for, runs it through the alert engine as it is now
        without sending anything, and returns one row per audit log alert that applies to the tenant: WouldAlert (Sent,
        Matches but another alert is sent first, Counts toward it for a repeated activity alert, or No), Reason in plain
        language, Outcome (Fires, AlsoMatches, CountsToward, Close, OtherActivity, OtherLog, Excluded or NotChecked), Matches
        (every condition of a group holds, whether or not the alert can send) and Groups: each
        OR group of the alert, whether it looks at this record's operation and matches, and each condition's property,
        operator, expected value, the record's actual value and whether it is met. A repeated activity alert is shown as
        counting the record when the record's operation is one it counts. Metadata names the record's operation, user
        and time.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = $Request.Query.tenantFilter
    # The LogId of the saved alert to check, as Saved Logs lists it.
    $LogId = $Request.Query.LogId
    if (-not $TenantFilter -or -not $LogId) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'tenantFilter and LogId are required' } })
    }
    $LogNames = @{
        'Audit.AzureActiveDirectory' = 'Entra ID'
        'Audit.Exchange'             = 'Exchange'
        'Audit.SharePoint'           = 'SharePoint and OneDrive'
        'Audit.General'              = 'General (Teams and more)'
    }

    try {
        $Table = Get-CIPPTable -TableName 'AuditLogs'
        $SafeTenant = ConvertTo-CIPPODataFilterValue -Value $TenantFilter -Type 'String'
        $SafeId = ConvertTo-CIPPODataFilterValue -Value $LogId -Type 'String'
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$SafeTenant' and RowKey eq '$SafeId'"
        if (-not $Row) { throw [System.Management.Automation.ItemNotFoundException]::new("No saved alert $LogId for $TenantFilter") }
        $Raw = ($Row.Data | ConvertFrom-Json).RawData
        # The audit record the alert was sent for; a repeated activity alert keeps a few sample records.
        $Records = if ($Raw.AuditRecord) {
            @(if ($Raw.AuditRecord -is [string]) { [CIPP.CippJson]::ConvertFromJson($Raw.AuditRecord) } else { $Raw.AuditRecord })
        } else { @($Raw) }
        $Records = @(foreach ($Record in $Records) { if ($Record) { $Record } })
        if ($Records.Count -eq 0) { throw [System.Management.Automation.ItemNotFoundException]::new('The saved alert has no audit record to check') }
        $Operations = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($Record in $Records) { [void]$Operations.Add([string]$Record.Operation) }
        # The log the record came from, by its workload: an alert reading another log never sees it.
        $RecordLog = switch ([string]$Records[0].Workload) {
            'AzureActiveDirectory' { 'Audit.AzureActiveDirectory' }
            'Exchange' { 'Audit.Exchange' }
            { $_ -in 'SharePoint', 'OneDrive' } { 'Audit.SharePoint' }
            default { 'Audit.General' }
        }

        $Evaluation = Test-CIPPAuditLogRules -TenantFilter $TenantFilter -Rows $Records -EvaluateOnly -AllMatches
        if ($Evaluation.Error) { throw $Evaluation.Error }
        # Per rule, its clauses (one per OR group) on every record; and the rule each record would actually alert on.
        $ByRule = @{}
        $SentBy = [System.Collections.Generic.HashSet[string]]::new()
        # The groups shown for a rule are its clauses on the first record.
        $Shown = @{}
        foreach ($Clause in @(@($Evaluation.RuleReports)[0].Clauses)) {
            if (-not $Shown.ContainsKey([string]$Clause.RuleKey)) { $Shown[[string]$Clause.RuleKey] = [System.Collections.Generic.List[object]]::new() }
            $Shown[[string]$Clause.RuleKey].Add($Clause)
        }
        foreach ($Report in @($Evaluation.RuleReports)) {
            $First = $Report.Clauses.Where({ $_.Anchored -and $_.Matched -and -not $_.Excluded }, 'First')
            if ($First.Count -gt 0) { [void]$SentBy.Add([string]$First[0].RuleKey) }
            foreach ($Clause in $Report.Clauses) {
                if (-not $ByRule.ContainsKey([string]$Clause.RuleKey)) { $ByRule[[string]$Clause.RuleKey] = [System.Collections.Generic.List[object]]::new() }
                $ByRule[[string]$Clause.RuleKey].Add($Clause)
            }
        }

        $Results = foreach ($Rule in @(Get-CIPPAuditLogRuleSet -TenantFilter $TenantFilter)) {
            # An alert without a comment is named by its conditions.
            $Name = if ($Rule.AlertComment) { [string]$Rule.AlertComment } else {
                $Summary = @(foreach ($Condition in @($Rule.Conditions | ConvertFrom-Json -ErrorAction SilentlyContinue)) { "$($Condition.Property.label) $($Condition.Operator.label) $(@($Condition.Input.value) -join ', ')" }) -join ' and '
                if ($Summary.Length -gt 120) { $Summary.Substring(0, 117) + '...' } else { $Summary }
            }
            $Clauses = if ($ByRule.ContainsKey([string]$Rule.RowKey)) { @($ByRule[[string]$Rule.RowKey]) } else { @() }
            $Hit = $Clauses.Where({ $_.Anchored -and $_.Matched }, 'First').Count -gt 0
            $Anchored = $Clauses.Where({ $_.Anchored }, 'First').Count -gt 0
            $Outcome = if ($Rule.LogType -and $Rule.LogType -ne $RecordLog) {
                @{ Code = 'OtherLog'; WouldAlert = 'No'; Reason = "This alert reads the $($LogNames[[string]$Rule.LogType] ?? $Rule.LogType) log, and this record is in the $($LogNames[$RecordLog]) log, so it can never fire on it." }
            } elseif ($Rule.Threshold) {
                $Setting = try { [string]$Rule.Threshold | ConvertFrom-Json -ErrorAction Stop } catch { $null }
                $Group = @(Split-CIPPAuditLogConditions -Conditions ($Rule.Conditions | ConvertFrom-Json -ErrorAction SilentlyContinue))
                $Anchor = if ($Group.Count -eq 1) { Get-CIPPAuditLogRuleAnchor -Conditions $Group[0].Conditions }
                $Counted = $Anchor -and @($Operations).Where({ $Anchor.Literals.Contains($_) }, 'First').Count -gt 0
                if ($Counted -and $TenantFilter -in $Rule.Excluded.value) {
                    @{ Code = 'Excluded'; WouldAlert = 'Would count toward it, but this tenant is excluded'; Reason = "A repeated activity alert this record would count toward, but this tenant is excluded from it." }
                } elseif ($Counted) {
                    @{ Code = 'CountsToward'; WouldAlert = 'Counts toward it'; Reason = "A repeated activity alert: this record counts toward it, and it alerts when one user or app does this $($Setting.Count) times within $($Setting.Minutes) minutes." }
                } else {
                    @{ Code = 'OtherActivity'; WouldAlert = 'No'; Reason = "A repeated activity alert that counts other operations, not '$(@($Operations) -join "', '")'." }
                }
            } elseif ($Clauses.Count -eq 0) {
                @{ Code = 'NotChecked'; WouldAlert = 'No'; Reason = 'The alert is not checked: each group of its conditions needs an Operation condition using Equals, In or Like.' }
            } elseif ($TenantFilter -in $Rule.Excluded.value -and $Anchored) {
                if ($Hit) {
                    @{ Code = 'Excluded'; WouldAlert = 'Would match, but this tenant is excluded'; Reason = 'Every condition matches, but this tenant is excluded from the alert, so nothing is sent.' }
                } else {
                    @{ Code = 'Excluded'; WouldAlert = 'Would not match, and this tenant is excluded'; Reason = 'This tenant is excluded from the alert, and not every condition matches either.' }
                }
            } elseif ($Hit) {
                if ($SentBy.Contains([string]$Rule.RowKey)) {
                    @{ Code = 'Fires'; WouldAlert = 'Sent'; Reason = 'Every condition matches, so this alert is sent.' }
                } else {
                    @{ Code = 'AlsoMatches'; WouldAlert = 'Matches, another alert is sent first'; Reason = 'Every condition matches, but an earlier alert also matches this record and only one alert is sent per record.' }
                }
            } elseif ($Anchored) {
                # The group that came closest: the one that looks at this operation, then the most conditions met.
                $Closest = @($Clauses.Where({ $_.Anchored }) | Sort-Object -Property @{ Expression = { @($_.Conditions).Where({ $_.Passed }).Count }; Descending = $true })[0]
                $Failed = @(@($Closest.Conditions).Where({ -not $_.Passed }).Condition)
                @{ Code = 'Close'; WouldAlert = 'No'; Reason = "Not every condition matches. Not met: $($Failed -join '; ')." }
            } else {
                @{ Code = 'OtherActivity'; WouldAlert = 'No'; Reason = "The alert looks for other operations, not '$(@($Operations) -join "', '")'." }
            }
            [pscustomobject]@{
                Alert      = $Name
                Log        = $LogNames[[string]$Rule.LogType] ?? $Rule.LogType
                WouldAlert = $Outcome.WouldAlert
                Reason     = $Outcome.Reason
                Outcome    = $Outcome.Code
                Matches    = $Hit
                Groups     = @(foreach ($Clause in @($Shown[[string]$Rule.RowKey] | Where-Object { $_ })) {
                        [pscustomobject]@{
                            Group               = $Clause.Group
                            LooksAtThisActivity = $Clause.Anchored
                            Matched             = $Clause.Anchored -and $Clause.Matched
                            Conditions          = @($Clause.Conditions)
                        }
                    })
                RuleKey    = $Rule.RowKey
            }
        }
        $First = $Records[0]
        $StatusCode = [HttpStatusCode]::OK
        $Body = @{
            Results  = @($Results | Sort-Object -Property @{ Expression = { @('Fires', 'AlsoMatches', 'Close', 'CountsToward', 'Excluded', 'NotChecked', 'OtherActivity', 'OtherLog').IndexOf($_.Outcome) } }, Alert)
            Metadata = @{ Operation = @($Operations) -join ', '; Log = $LogNames[$RecordLog]; User = $First.UserId; CreationTime = $First.CreationTime; Records = $Records.Count }
        }
    } catch {
        $StatusCode = Get-CippErrorStatusCode -ErrorRecord $_
        $Body = @{ Results = "Could not check the saved alert against the current alerts: $($_.Exception.Message)" }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
