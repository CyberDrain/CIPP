function Build-CippBaselineWhatIfReportTree {
    <#
    .SYNOPSIS
        Compose the Baseline What-If report as a component tree (server port of CippBaselineWhatIfReport.jsx).
    .DESCRIPTION
        Pure composition from an already-gathered alignment payload: what applying the configured
        standards would change today, what each planned stage will change, optionally what assigning
        one more baseline would roll out, and the deviations that have been agreed and will be left
        alone. Nothing is changed by producing it. Returns @{ Blocks; Variables }.
    .PARAMETER Data
        TenantName, TenantFilter, summary (alignedPercentage, verifiedPercentage), rows[] (the
        resolved standards rows), stageStates[] (per assigned baseline), simulatedTemplate (a baseline
        not assigned to the tenant, or $null) and catalog[] (the definition catalog: name, label,
        executiveText).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$Data)

    $summary = if ($Data.summary) { $Data.summary } else { @{} }
    # `?? @()` so a missing list is empty rather than @($null), which would render as one blank row.
    $rows = @($Data.rows ?? @())
    $stageStates = @($Data.stageStates ?? @())
    $simulated = $Data.simulatedTemplate
    $catalog = @{}
    foreach ($entry in @($Data.catalog ?? @())) { if ($entry.name) { $catalog[[string]$entry.name] = $entry } }
    function nz($v) { if ($null -eq $v) { 0 } else { [int]$v } }
    function plural($c, $s, $p) { "$c $(if ($c -eq 1) { $s } else { if ($p) { $p } else { "${s}s" } })" }
    function html($s) { [System.Net.WebUtility]::HtmlEncode([string]$s) }

    # A standard's plain-language line for an executive reader, falling back to its label.
    $textFor = {
        param($name, $fallback)
        $entry = $catalog[[string]$name]
        if ($entry -and $entry.executiveText) { [string]$entry.executiveText } else { [string]$fallback }
    }
    $labelFor = {
        param($name)
        $entry = $catalog[[string]$name]
        if ($entry -and $entry.label) { [string]$entry.label } else { [string]$name }
    }

    # A stage's graduation conditions in words (client describeStageConditions).
    $operatorLabels = @{ eq = 'equals'; ne = 'does not equal'; startsWith = 'starts with'; notStartsWith = 'does not start with' }
    $describeConditions = {
        param($stage)
        $conditions = @($stage.conditions ?? @())
        if ($conditions.Count -eq 0) { return 'no conditions configured' }
        $parts = foreach ($c in $conditions) {
            switch ([string]$c.type) {
                'time' { "$($c.days) $($c.unit ?? 'days') in the previous stage" }
                'variable' { "$($c.variable) $($operatorLabels[[string]$c.operator] ?? $c.operator) '$($c.value)'" }
                'success' { 'all previous stage items applied successfully' }
                'manual' { 'manual approval by an operator' }
                default { [string]$c.type }
            }
        }
        $parts -join $(if ($stage.logic -eq 'or') { ' OR ' } else { ' AND ' })
    }
    # When a time condition will be met, from the day the tenant entered its current stage.
    $estimatedAt = {
        param($state)
        $time = @($state.nextStage.conditions ?? @()) | Where-Object { $_.type -eq 'time' } | Select-Object -First 1
        if (-not $time) { return $null }
        $entered = if ($state.enteredStageAt -is [DateTimeOffset]) { $state.enteredStageAt.UtcDateTime } else { $state.enteredStageAt -as [datetime] }
        if (-not $entered) { return $null }
        $days = ([double]($time.days ?? 0)) * $(if ($time.unit -eq 'weeks') { 7 } else { 1 })
        $entered.AddDays($days).ToString('MMMM d, yyyy')
    }

    $changesNow = @($rows | Where-Object { @('Drift', 'Partially Accepted', 'Denied - Remediate Pending', 'Denied - Delete Pending') -contains $_.status })
    $accepted = @($rows | Where-Object { $_.status -eq 'Accepted' })
    $planned = @($stageStates | Where-Object { $_.nextStage })

    $blocks = [System.Collections.Generic.List[object]]::new()

    # -- Where you stand today --
    $blocks.Add((New-CippReportPage -Title 'Baseline What-If Report' -Subtitle 'What applying the configured standards would change'))
    $blocks.Add((New-CippReportParagraph -Html ('<p>This report previews what applying the standards configured for <b>{0}</b> would change: what would change today, what each planned stage will change when it is reached, and the deviations that have been agreed and will be left alone. No changes have been made by producing it.</p>' -f (html $Data.TenantName))))
    $blocks.Add((New-CippReportHeading -Title 'Where you stand today'))
    $blocks.Add((New-CippReportStatRow -Stats @(
                @{ value = "$(nz $summary.alignedPercentage)%"; label = 'Compliant incl. accepted deviations' }
                @{ value = "$(nz $summary.verifiedPercentage)%"; label = 'Compliant with baseline' }
                @{ value = $changesNow.Count; label = 'Changes to make' }
                @{ value = $accepted.Count; label = 'Agreed exceptions' }
            )))

    # -- Changes we would make now --
    $blocks.Add((New-CippReportHeading -Title "Changes we would make now ($($changesNow.Count))"))
    if ($changesNow.Count -eq 0) {
        $blocks.Add((New-CippReportClearBox -Title 'Nothing to change' -Content 'Every enforced standard is already in its expected state.'))
    } else {
        $blocks.Add((New-CippReportBullets -Items @($changesNow | ForEach-Object {
                        $meta = @(
                            if ($_.impact) { [string]$_.impact }
                            if ((nz $_.secureScoreImpact) -gt 0) { "increases Secure Score by up to $(nz $_.secureScoreImpact) points" }
                            if ([string]$_.status -like 'Denied*') { 'deviation denied, fix pending' }
                        ) -join ' - '
                        @{ label = [string]$_.standardLabel; text = "$(& $textFor $_.standardName $_.standardLabel)$(if ($meta) { " ($meta)" })" }
                    })))
    }

    # -- Planned future changes --
    $blocks.Add((New-CippReportHeading -Title 'Planned future changes (staged rollout)'))
    if ($planned.Count -eq 0) {
        $blocks.Add((New-CippReportClearBox -Title 'No further staged changes' -Content 'This tenant is in the final stage of every assigned baseline.'))
    }
    foreach ($state in $planned) {
        $when = & $estimatedAt $state
        $blocks.Add((New-CippReportInfoBox -Title ([string]$state.templateName) -Content ('Currently in Stage {0} of {1} ({2}). Next: Stage {3} ({4}) - advances when {5}{6}.' -f (nz $state.currentStage), (nz $state.totalStages), $state.stageName, ((nz $state.currentStage) + 1), $state.nextStageName, (& $describeConditions $state.nextStage), $(if ($when) { ", estimated around $when" }))))
        $standards = @($state.nextStage.standards ?? @()) | ForEach-Object { ([string]$_).Split('#')[0] } | Select-Object -Unique
        $items = @($standards | Where-Object { $catalog.ContainsKey([string]$_) } | ForEach-Object { @{ label = (& $labelFor $_); text = (& $textFor $_ $_) } })
        if ($items.Count -gt 0) { $blocks.Add((New-CippReportBullets -Items $items)) }
    }

    # -- What-if: one more baseline --
    if ($simulated) {
        $blocks.Add((New-CippReportPage -Title "What-if: assigning the $($simulated.templateName) baseline" -Subtitle 'What one more baseline would roll out, stage by stage'))
        $blocks.Add((New-CippReportParagraph -Text ("$(if ($simulated.description) { "$($simulated.description). " })This baseline is not assigned to the tenant today - below is what assigning it would roll out, stage by stage.")))
        $stageIndex = 0
        foreach ($stage in @($simulated.stages ?? @())) {
            $stageIndex++
            $timing = if ($stageIndex -eq 1) { 'applies immediately' } else { "advances when $(& $describeConditions $stage)" }
            $blocks.Add((New-CippReportHeading -Title "Stage ${stageIndex}: $($stage.name) - $timing"))
            $standards = @($stage.standards ?? @()) | ForEach-Object { ([string]$_).Split('#')[0] } | Select-Object -Unique
            $items = @($standards | Where-Object { $catalog.ContainsKey([string]$_) } | ForEach-Object {
                    $name = [string]$_
                    $current = $rows | Where-Object { $_.standardName -eq $name } | Select-Object -First 1
                    $effect = if ($current -and $current.status -eq 'Compliant') { "No change - already aligned today (configured by $($current.sourceTemplate))." } else { 'Would change this tenant when the stage applies.' }
                    @{ label = (& $labelFor $name); text = "$(& $textFor $name $name) $effect" }
                })
            if ($items.Count -gt 0) { $blocks.Add((New-CippReportBullets -Items $items)) }
            else { $blocks.Add((New-CippReportNote -Text 'No catalogued standards in this stage.')) }
        }
    }

    # -- Agreed exceptions --
    if ($accepted.Count -gt 0) {
        $blocks.Add((New-CippReportHeading -Title "Agreed exceptions we will not change ($($accepted.Count))"))
        $blocks.Add((New-CippReportBullets -Items @($accepted | ForEach-Object { @{ label = [string]$_.standardLabel; text = $(if ($_.deviationReason) { [string]$_.deviationReason } else { 'Accepted deviation.' }) } })))
    }

    @{
        Blocks    = @($blocks)
        Variables = @{
            coverlabel         = 'Baseline What-If'
            coversubtitle      = "What applying the configured standards would change at $($Data.TenantName), today and at each planned stage. No changes have been made."
            covermeta          = ('{0} to make / {1} / {2}' -f (plural $changesNow.Count 'change'), (plural $planned.Count 'staged rollout'), (plural $accepted.Count 'agreed exception'))
            covermetanote      = "Compliant with baseline: $(nz $summary.verifiedPercentage)%"
            coverfooternote    = 'What-if preview - no changes were made'
            coverfallbackimage = '/reportImages/working.jpg'
            footerlabel        = "$($Data.TenantName) - Baseline What-If"
        }
    }
}
