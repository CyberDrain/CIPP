# Every audit log preset in frontend/src/data/AuditLogTemplates.json, run end to end against real audit records
# (scrubbed) from Fixtures/AuditLogPresetSamples.json. Each preset is stored the way Invoke-AddAlert stores a rule,
# loaded by Get-CIPPAuditLogRuleSet, sanitised by Test-CIPPConditionFilter and matched by Test-CIPPAuditLogRules; the
# assertion is on what reaches Invoke-CippWebhookProcessing. Only storage, Graph and the geo-IP lookup are mocked.
#
# A case lists the samples the preset must alert on (trigger) and near misses it must ignore (noTrigger). Conditions
# the user fills in when adding the alert (an empty Input, e.g. the allowed countries) take the case's input, and the
# geo-IP answer for a sample's client IP comes from the case's geo.

BeforeDiscovery {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Templates = Get-Content (Join-Path (Split-Path -Parent $RepoRoot) 'frontend/src/data/AuditLogTemplates.json') -Raw | ConvertFrom-Json
    $Fixture = Get-Content (Join-Path $PSScriptRoot 'Fixtures/AuditLogPresetSamples.json') -Raw | ConvertFrom-Json
    $Cases = @($Fixture.cases)

    $TriggerCases = foreach ($Case in $Cases) { foreach ($Sample in @($Case.trigger)) { @{ Preset = $Case.preset; Sample = $Sample } } }
    $QuietCases = foreach ($Case in $Cases) { foreach ($Sample in @($Case.noTrigger)) { @{ Preset = $Case.preset; Sample = $Sample } } }
    $CoverageCases = foreach ($Template in $Templates) {
        $Case = $Cases.Where({ $_.preset -eq $Template.value }, 'First')[0]
        @{ Preset = $Template.value; Triggers = @($Case.trigger).Where({ $_ }).Count; Quiet = @($Case.noTrigger).Where({ $_ }).Count; Pending = [string]$Case.pending }
    }
    $FixtureCases = foreach ($Case in $Cases) { @{ Preset = $Case.preset; Known = $Templates.value -contains $Case.preset } }
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    $script:Templates = Get-Content (Join-Path (Split-Path -Parent $RepoRoot) 'frontend/src/data/AuditLogTemplates.json') -Raw | ConvertFrom-Json
    $script:Fixture = Get-Content (Join-Path $PSScriptRoot 'Fixtures/AuditLogPresetSamples.json') -Raw | ConvertFrom-Json
    $script:Tenant = 'contoso.onmicrosoft.com'

    function Get-CIPPTable { param($TableName) }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property, $First) }
    function Get-AzDataTableEntity { param($TableName, $Context, $Filter, $Property, $First) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force, $OperationType) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Remove-AzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Expand-CIPPTenantGroups { param($TenantFilter) }
    function Invoke-CippWebhookProcessing { param($Data, $CIPPURL, $TenantFilter, $AlertComment, $PendingAuditLogWrites) }
    function Get-CIPPGeoIPLocationBatch { param($IPs) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) [pscustomobject]@{ NormalizedError = "$Exception" } }
    function Get-CIPPTestData { param($TenantFilter, $Type, $Fields, [switch]$NoProjection) }
    function New-GraphBulkRequest { param($Requests, $AsApp, $TenantId) }
    function New-GraphGetRequest { param($uri, $tenantid, $AsApp, [switch]$Stream, $ComplexFilter, $NoPagination) }
    function Get-CIPPPartnerUserLookup { @{} }

    foreach ($Helper in @(
            'Authentication/Get-CIPPIPAllowBlockList.ps1'
            'Authentication/Resolve-CIPPIPAllowBlockList.ps1'
            'Authentication/Test-IpInRange.ps1'
            'Authentication/ConvertTo-CIPPIPRange.ps1'
            'BEC/ConvertTo-CIPPBecHostAddress.ps1'
            'Tools/Test-CIPPConditionFilter.ps1'
            'Webhooks/Get-CIPPAuditLogRuleSet.ps1'
            'Webhooks/Test-CIPPAuditLogRules.ps1'
            'Webhooks/Get-CIPPAuditLogPrefilter.ps1'
            'Webhooks/Select-CIPPAuditLogCandidate.ps1'
            'Webhooks/Get-CIPPAuditLogRuleAnchor.ps1'
            'Webhooks/Split-CIPPAuditLogConditions.ps1'
        )) {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$Helper")
    }

    # Runs one preset against one sample and returns the records that were dispatched for alerting. -Feed takes the
    # Management Activity feed path instead: the raw record (no auditData wrapper) through the prefilter and the feed's
    # -EvaluateOnly pass, then the stored AuditRecord through the post-exec evaluation that dispatches.
    function Invoke-PresetSample {
        # -Extra adds conditions to the preset's; -Report returns the engine's per-rule report for the raw record instead.
        param([string]$Preset, [string]$Sample, [switch]$Feed, [object[]]$Extra, [switch]$Report)
        $Template = $script:Templates.Where({ $_.value -eq $Preset }, 'First')[0]
        $Case = @($script:Fixture.cases).Where({ $_.preset -eq $Preset }, 'First')[0]
        $Record = $script:Fixture.samples.$Sample
        if (-not $Record) { throw "Sample '$Sample' is not in the fixture" }

        $Conditions = foreach ($Condition in $Template.template.conditions) {
            $Copy = $Condition | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            if ($null -eq $Copy.Input -or ($Copy.Input -isnot [array] -and [string]::IsNullOrEmpty($Copy.Input.value))) {
                $Copy | Add-Member -NotePropertyName Input -NotePropertyValue $Case.input.($Copy.Property.label) -Force
            }
            $Copy
        }
        $Conditions = @($Conditions) + @($Extra | Where-Object { $_ })
        # Same serialisation Invoke-AddAlert stores.
        $script:RuleRow = [pscustomobject]@{
            PartitionKey      = 'Webhookv2'
            RowKey            = "fixture-$Preset"
            Tenants           = (@(@{ label = 'Contoso'; value = $script:Tenant }) | ConvertTo-Json -Compress -Depth 10 | Out-String)
            excludedTenants   = $null
            Conditions        = (@($Conditions) | ConvertTo-Json -Compress -Depth 10 | Out-String)
            Actions           = '[]'
            Type              = $Template.template.logbook.value
            AlertComment      = $Preset
            CustomSubject     = ''
            PsaTicketPriority = ''
        }

        $script:GeoByIp = @{}
        $Geo = $Case.geo.$Sample
        $ClientIp = [string]$Record.auditData.ClientIP
        if ($Geo -and $ClientIp) {
            $Ip = $ClientIp -replace '^\[?([0-9a-fA-F:.]+?)\]?(:\d+)?$', '$1'
            $script:GeoByIp[$Ip] = [pscustomobject]@{ CountryOrRegion = $Geo.CountryOrRegion; Proxy = [bool]$Geo.Proxy; Hosting = [bool]$Geo.Hosting }
        }

        $script:AuditRuleSetCache = $null
        $script:AuditRuleSearchLookups = $null
        $script:AuditRuleLookupCache = @{}
        $script:AuditRuleListCache = @{}
        $script:PartnerUserMemo = $null
        $script:Dispatched = [System.Collections.Generic.List[object]]::new()

        if ($Report) {
            $Raw = [CIPP.CippJson]::ConvertFromJson(($Record.auditData | ConvertTo-Json -Depth 20 -Compress))
            return , @((Test-CIPPAuditLogRules -TenantFilter $script:Tenant -Rows @($Raw) -EvaluateOnly -AllMatches 3>$null 6>$null).RuleReports)
        }
        if ($Feed) {
            $Raw = [CIPP.CippJson]::ConvertFromJson(($Record.auditData | ConvertTo-Json -Depth 20 -Compress))
            $Prefilter = Get-CIPPAuditLogPrefilter -TenantFilter $script:Tenant
            if ($null -ne $Prefilter -and $null -eq (Select-CIPPAuditLogCandidate -Prefilter $Prefilter -Records @($Raw))) { return , @() }
            $Evaluated = Test-CIPPAuditLogRules -TenantFilter $script:Tenant -Rows @($Raw) -EvaluateOnly 3>$null 6>$null
            $Stored = @(foreach ($Data in @($Evaluated.DataToProcess)) { if ($Data.AuditRecord) { [CIPP.CippJson]::ConvertFromJson([string]$Data.AuditRecord) } })
            if ($Stored.Count -eq 0) { return , @() }
            $script:AuditRuleSearchLookups = $null
            $null = Test-CIPPAuditLogRules -TenantFilter $script:Tenant -Rows $Stored -CachePartitionKey "$($script:Tenant)|feed" -CallerSweepsCachePartition 3>$null 6>$null
            return , $script:Dispatched.ToArray()
        }

        # The pipeline stores each record as JSON in CacheWebhooks and parses it back with CippJson before matching.
        $Row = [CIPP.CippJson]::ConvertFromJson(($Record | ConvertTo-Json -Depth 20 -Compress))
        $null = Test-CIPPAuditLogRules -TenantFilter $script:Tenant -Rows @($Row) -CachePartitionKey "$($script:Tenant)|fixture" -CallerSweepsCachePartition 3>$null 6>$null
        , $script:Dispatched.ToArray()
    }
}

Describe 'Audit log presets on real audit records' {
    BeforeEach {
        Mock -CommandName Get-CIPPTable -MockWith { param($TableName) @{ TableName = $TableName } }
        Mock -CommandName Get-CIPPAzDataTableEntity -MockWith {
            param($TableName, $Context, $Filter, $Property, $First)
            switch ($TableName) {
                'WebhookRules' { $script:RuleRow }
                'cacheauditloglookups' {
                    foreach ($Key in 'users', 'groups', 'devices', 'servicePrincipals') {
                        [pscustomobject]@{ PartitionKey = $script:Tenant; RowKey = $Key; Format = 'hashtable'; Data = '{}' }
                    }
                }
                'Config' { [pscustomobject]@{ Value = 'cipp.contoso.com' } }
                default { @() }
            }
        }
        Mock -CommandName Get-AzDataTableEntity -MockWith { @() }
        Mock -CommandName Add-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-CIPPAzDataTableEntity -MockWith { }
        Mock -CommandName Remove-AzDataTableEntity -MockWith { }
        Mock -CommandName Expand-CIPPTenantGroups -MockWith { param($TenantFilter) [pscustomobject]@{ value = @($TenantFilter.value) } }
        Mock -CommandName Invoke-CippWebhookProcessing -MockWith { param($Data) $script:Dispatched.Add($Data) }
        Mock -CommandName Get-CIPPGeoIPLocationBatch -MockWith { $script:GeoByIp }
        Mock -CommandName Write-LogMessage -MockWith { }
        Mock -CommandName Get-CIPPTestData -MockWith { @() }
        Mock -CommandName New-GraphBulkRequest -MockWith { @() }
        Mock -CommandName New-GraphGetRequest -MockWith { @() }
    }

    It '<Preset> alerts on <Sample>' -ForEach $TriggerCases {
        $Dispatched = Invoke-PresetSample -Preset $Preset -Sample $Sample
        $Expected = $script:Fixture.samples.$Sample.auditData.Id
        @($Dispatched).Count | Should -Be 1 -Because "the preset should match the real '$Sample' record"
        @($Dispatched)[0].Id | Should -Be $Expected
    }

    It '<Preset> ignores <Sample>' -ForEach $QuietCases {
        $Dispatched = Invoke-PresetSample -Preset $Preset -Sample $Sample
        @($Dispatched).Count | Should -Be 0 -Because "'$Sample' is a near miss the preset must not alert on"
    }

    It '<Preset> alerts on <Sample> from the activity feed' -ForEach $TriggerCases {
        $Dispatched = Invoke-PresetSample -Preset $Preset -Sample $Sample -Feed
        @($Dispatched).Count | Should -Be 1 -Because "the feed must neither prefilter out nor fail to store the real '$Sample' record"
        @($Dispatched)[0].Id | Should -Be $script:Fixture.samples.$Sample.auditData.Id
    }

    It '<Preset> ignores <Sample> from the activity feed' -ForEach $QuietCases {
        $Dispatched = Invoke-PresetSample -Preset $Preset -Sample $Sample -Feed
        @($Dispatched).Count | Should -Be 0 -Because "'$Sample' is a near miss the preset must not alert on"
    }

    It '<Preset> has real samples it must and must not alert on' -ForEach $CoverageCases {
        if ($Triggers -eq 0 -or $Quiet -eq 0) {
            Set-ItResult -Skipped -Because ($Pending ? $Pending : 'no real audit sample captured yet')
            return
        }
        $Triggers | Should -BeGreaterThan 0
        $Quiet | Should -BeGreaterThan 0
    }

    It 'fixture case <Preset> names a preset that exists' -ForEach $FixtureCases {
        $Known | Should -BeTrue
    }

    It 'a condition for every group applies inside each group of an OR alert (<Sample>)' -ForEach @(
        @{ Sample = 'exo-new-inboxrule-forward' }, @{ Sample = 'exo-set-mailbox-forwarding-external' }
    ) {
        # The record's Id is never rewritten by the engine, so leaving it out proves the shared condition reaches the group.
        $LeaveOut = { param($Value) [pscustomobject]@{ Property = @{ value = 'String'; label = 'Id' }; Operator = @{ value = 'notlike'; label = 'Not like' }; Input = @{ value = $Value }; Group = -1 } }
        foreach ($Feed in $false, $true) {
            $Dispatched = Invoke-PresetSample -Preset 'MailForwardedOut' -Sample $Sample -Feed:$Feed -Extra @(& $LeaveOut ([string]$script:Fixture.samples.$Sample.auditData.Id))
            @($Dispatched).Count | Should -Be 0
            $Dispatched = Invoke-PresetSample -Preset 'MailForwardedOut' -Sample $Sample -Feed:$Feed -Extra @(& $LeaveOut 'some-other-record')
            @($Dispatched).Count | Should -Be 1
        }
    }

    It 'a UTC time window holds the times inside it, including one that crosses midnight' {
        $Record = [pscustomobject]@{ CIPPTimeUtc = '23:30' }
        $Holds = {
            param($Operator, $Window)
            $Test = Test-CIPPConditionFilter -Condition ([pscustomobject]@{ Property = @{ label = 'CIPPTimeUtc' }; Operator = @{ value = $Operator }; Input = @{ value = $Window } }) 3>$null
            if ($null -eq $Test) { return 'blocked' }
            @($Record).Where([scriptblock]::Create($Test)).Count -gt 0
        }
        & $Holds 'between' '22:00-06:00' | Should -BeTrue
        & $Holds 'between' '07:00-19:00' | Should -BeFalse
        & $Holds 'notbetween' '07:00-19:00' | Should -BeTrue
        & $Holds 'notbetween' '22:00-06:00' | Should -BeFalse
        & $Holds 'between' '23:30-23:45' | Should -BeTrue
        & $Holds 'between' '23:00-23:30' | Should -BeFalse
        & $Holds 'between' '7:00-19:00' | Should -Be 'blocked'
        & $Holds 'between' "07:00-19:00') -or ('" | Should -Be 'blocked'
    }

    It 'gives a regular expression a time limit, so a crafted value cannot hold the worker' {
        $Holds = {
            param($Operator, $Value)
            $Test = Test-CIPPConditionFilter -Condition ([pscustomobject]@{ Property = @{ label = 'UserAgent' }; Operator = @{ value = $Operator }; Input = @{ value = '^(\w+\s?)*/' } })
            @([pscustomobject]@{ UserAgent = $Value }).Where([scriptblock]::Create($Test)).Count -gt 0
        }
        & $Holds 'match' 'Mozilla/5.0' | Should -BeTrue
        & $Holds 'notmatch' 'Mozilla/5.0' | Should -BeFalse
        & $Holds 'notmatch' 'curl 8' | Should -BeTrue
        $Sw = [System.Diagnostics.Stopwatch]::StartNew()
        & $Holds 'notmatch' (('a' * 40) + '!') | Should -BeTrue
        & $Holds 'match' (('a' * 40) + '!') | Should -BeFalse
        $Sw.Elapsed.TotalSeconds | Should -BeLessThan 2
    }

    It 'sends at most 50 alerts per rule in one collection run, and says so once' {
        $Rows = @(foreach ($n in 1..60) { [CIPP.CippJson]::ConvertFromJson(($script:Fixture.samples.'exo-new-inboxrule-forward'.auditData | ConvertTo-Json -Depth 20 -Compress)) | ForEach-Object { $_.Id = "flood-$n"; $_ } })
        $null = Invoke-PresetSample -Preset 'MailForwardedOut' -Sample 'exo-new-inboxrule-forward' -Report
        $Counts = @{}
        $First = Test-CIPPAuditLogRules -TenantFilter $script:Tenant -Rows $Rows[0..39] -EvaluateOnly -AlertCounts $Counts 3>$null 6>$null
        $Second = Test-CIPPAuditLogRules -TenantFilter $script:Tenant -Rows $Rows[40..59] -EvaluateOnly -AlertCounts $Counts 3>$null 6>$null
        @($First.DataToProcess).Count + @($Second.DataToProcess).Count | Should -Be 50
        Should -Invoke Write-LogMessage -Times 1 -Exactly -ParameterFilter { $message -like '*matched more than 50 records*' }
    }

    It 'alerts only on records inside a UTC time window, day or date (<Sample>)' -ForEach @(@{ Sample = 'exo-new-inboxrule-forward' }) {
        $When = $script:Fixture.samples.$Sample.auditData.CreationTime
        $When = if ($When -is [datetime]) { if ($When.Kind -eq 'Local') { $When.ToUniversalTime() } else { $When } } else { [datetime]::Parse([string]$When, [cultureinfo]::InvariantCulture, 'AssumeUniversal,AdjustToUniversal') }
        $For = { param($Label, $Operator, $Value) [pscustomobject]@{ Property = @{ value = 'String'; label = $Label }; Operator = @{ value = $Operator; label = $Operator }; Input = @{ value = $Value }; Group = -1 } }
        $Around = '{0:HH:mm}-{1:HH:mm}' -f $When.AddMinutes(-30), $When.AddMinutes(30)
        $OtherDay = $When.AddDays(1).DayOfWeek.ToString()
        foreach ($Feed in $false, $true) {
            $Dispatched = Invoke-PresetSample -Preset 'MailForwardedOut' -Sample $Sample -Feed:$Feed -Extra @(& $For 'CIPPTimeUtc' 'between' $Around)
            @($Dispatched).Count | Should -Be 1
            $Dispatched = Invoke-PresetSample -Preset 'MailForwardedOut' -Sample $Sample -Feed:$Feed -Extra @(& $For 'CIPPTimeUtc' 'notbetween' $Around)
            @($Dispatched).Count | Should -Be 0
            $Dispatched = Invoke-PresetSample -Preset 'MailForwardedOut' -Sample $Sample -Feed:$Feed -Extra @(& $For 'CIPPDayUtc' 'eq' $When.DayOfWeek.ToString())
            @($Dispatched).Count | Should -Be 1
            $Dispatched = Invoke-PresetSample -Preset 'MailForwardedOut' -Sample $Sample -Feed:$Feed -Extra @(& $For 'CIPPDayUtc' 'eq' $OtherDay)
            @($Dispatched).Count | Should -Be 0
            $Dispatched = Invoke-PresetSample -Preset 'MailForwardedOut' -Sample $Sample -Feed:$Feed -Extra @(& $For 'CIPPDateUtc' 'gt' $When.AddDays(-1).ToString('yyyy-MM-dd'))
            @($Dispatched).Count | Should -Be 1
            $Dispatched = Invoke-PresetSample -Preset 'MailForwardedOut' -Sample $Sample -Feed:$Feed -Extra @(& $For 'CIPPDateUtc' 'lt' $When.ToString('yyyy-MM-dd'))
            @($Dispatched).Count | Should -Be 0
        }
        # The evaluation shows the record's UTC time against the window.
        $Reports = Invoke-PresetSample -Preset 'MailForwardedOut' -Sample $Sample -Report -Extra @(& $For 'CIPPTimeUtc' 'between' $Around)
        @(@($Reports[0].Clauses)[0].Conditions).Where({ $_.Property -eq 'CIPPTimeUtc' })[0].Actual | Should -Be $When.ToString('HH:mm')
    }

    It 'reports, for every group of every alert, whether each condition holds on a record' {
        $Reports = Invoke-PresetSample -Preset 'MailForwardedOut' -Sample 'exo-set-inboxrule-plain' -Report
        $Reports | Should -HaveCount 1
        $Clauses = @($Reports[0].Clauses)
        $Clauses.Group | Should -Be @(0, 1, 2)
        $Clauses.Matched | Should -Be @($false, $false, $false)
        $Clauses.Anchored | Should -Be @($true, $true, $false)
        @($Clauses[0].Conditions).Where({ -not $_.Passed }).Condition | Should -Be @('ForwardTo is Like *@*')
        # Each condition carries what it expects and what the record holds, as the engine sees it.
        $Operation = @($Clauses[0].Conditions).Where({ $_.Property -eq 'Operation' })[0]
        $Operation.Actual | Should -Be 'Set-InboxRule'
        $Operation.Expected | Should -Be 'New-InboxRule, Set-InboxRule'
        $Operation.Operator | Should -Be 'In'
        $Matched = Invoke-PresetSample -Preset 'MailForwardedOut' -Sample 'exo-set-inboxrule-redirect' -Report
        @($Matched[0].Clauses).Where({ $_.Matched }).Group | Should -Be @(1)
    }
}
