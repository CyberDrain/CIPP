# Pins the audit log prefilter against the real rule engine. Every scenario runs the same rules through
# Get-CIPPAuditLogPrefilter + Select-CIPPAuditLogCandidate on the raw records and through Test-CIPPAuditLogRules (shaping
# included), and asserts the prefilter keeps every record the engine matches. Where every condition can be tested on the
# raw record and nothing shadows it, the two must agree exactly, so the prefilter is also shown to drop what it can.

BeforeDiscovery {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $script:Presets = @(Get-Content -Raw (Join-Path (Split-Path -Parent $RepoRoot) 'frontend/src/data/AuditLogTemplates.json') | ConvertFrom-Json | ForEach-Object { @{ Name = $_.value; Conditions = @($_.template.conditions) } })
}

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    Add-Type -Path (Join-Path $RepoRoot 'Shared/CIPPSharp/bin/CIPPSharp.dll')
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity {
        param($TableName, $Context, $Filter, $Property, $First)
        switch ($TableName) {
            'WebhookRules' { $script:RuleRows }
            'cacheauditloglookups' { $script:DirectoryReads++; foreach ($Key in 'users', 'groups', 'devices', 'servicePrincipals') { [pscustomobject]@{ PartitionKey = 'contoso.com'; RowKey = $Key; Format = 'hashtable'; Data = '{}' } } }
            'Config' { [pscustomobject]@{ Value = 'cipp.contoso.com' } }
        }
    }
    function Get-AzDataTableEntity { param($TableName, $Context, $Filter, $Property, $First) }
    function Add-AzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force, $OperationType) }
    function Remove-AzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Expand-CIPPTenantGroups { param($TenantFilter) foreach ($Tenant in @($TenantFilter)) { [pscustomobject]@{ value = $Tenant.value ?? $Tenant } } }
    function Get-CIPPIPAllowBlockList { param($TenantFilter) @() }
    function Get-CIPPGeoIPLocationBatch { param($IPs) @{} }
    function Get-CIPPPartnerUserLookup { @{} }
    function Invoke-CippWebhookProcessing { param($Data, $CIPPURL, $TenantFilter, $AlertComment, $PendingAuditLogWrites) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData) }
    function Get-CippException { param($Exception) }
    foreach ($Helper in 'Webhooks/Test-CIPPAuditLogRules.ps1', 'Webhooks/Get-CIPPAuditLogRuleSet.ps1', 'Webhooks/New-CippAuditLogClaimRow.ps1', 'Webhooks/Get-CIPPAuditLogPrefilter.ps1', 'Webhooks/Select-CIPPAuditLogCandidate.ps1', 'Webhooks/Get-CIPPAuditLogRuleAnchor.ps1', 'Tools/Test-CIPPConditionFilter.ps1') {
        . (Join-Path $RepoRoot "Modules/CIPPCore/Public/$Helper")
    }

    function New-Condition([string]$Property, [string]$Operator, $Value) {
        @{ Property = @{ label = $Property; value = 'String' }; Operator = @{ label = $Operator; value = $Operator }; Input = @{ value = $Value } }
    }
    # One WebhookRules row per rule; each rule is an array of conditions.
    function Set-Rules([object[]]$Rules, [string[]]$Excluded) {
        $i = 0
        $script:RuleRows = foreach ($Conditions in $Rules) {
            $i++
            [pscustomobject]@{
                PartitionKey = 'WebhookRules'; RowKey = "rule-$i"; Tenants = '[{"value":"AllTenants"}]'; Type = 'Audit.AzureActiveDirectory'
                excludedTenants = if ($Excluded -contains "rule-$i") { '[{"value":"contoso.com"}]' } else { $null }
                Conditions = ConvertTo-Json -InputObject @($Conditions) -Depth 6 -Compress; Actions = '[]'; AlertComment = ''; CustomSubject = ''; PsaTicketPriority = ''
            }
        }
    }
    # Records parsed the way the feed and the cache read them, so both sides start from the same raw shape.
    function ConvertTo-Records([object[]]$Records, [switch]$Graph) {
        foreach ($Record in $Records) {
            $Raw = [CIPP.CippJson]::ConvertFromJson((ConvertTo-Json -InputObject $Record -Depth 8 -Compress))
            if ($Graph) { [pscustomobject]@{ id = $Raw.Id; operation = $Raw.Operation; auditData = $Raw } } else { $Raw }
        }
    }
    # Kept by the prefilter and matched by the engine, each a sorted list of record Ids.
    function Compare-Prefilter([object[]]$Rules, [object[]]$Records, [string[]]$Excluded, [switch]$Graph) {
        Set-Rules $Rules $Excluded
        $script:AuditRuleSetCache = $null
        $Prefilter = Get-CIPPAuditLogPrefilter -TenantFilter 'contoso.com'
        $Kept = @(Select-CIPPAuditLogCandidate -Prefilter $Prefilter -Records @(ConvertTo-Records $Records -Graph:$Graph) | ForEach-Object { [string]($_.auditData.Id ?? $_.Id) })
        foreach ($Name in 'AuditRuleSetCache', 'AuditRuleSearchLookups', 'AuditRuleListCache') { Set-Variable -Scope Script -Name $Name -Value $null }
        $Result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(ConvertTo-Records $Records -Graph:$Graph) -CachePartitionKey 'contoso.com|test' -CallerSweepsCachePartition 3>$null 6>$null
        [pscustomobject]@{
            Prefilter = $Prefilter
            Kept      = @($Kept | Sort-Object -Unique)
            Matched   = @(@($Result.DataToProcess) | ForEach-Object { [string]$_.Id } | Sort-Object -Unique)
        }
    }
    function Assert-NoMissed($Comparison) {
        @($Comparison.Matched | Where-Object { $_ -notin $Comparison.Kept }) | Should -BeNullOrEmpty -Because 'the prefilter must keep every record the engine matches'
    }

    # A record built to satisfy each condition of a rule as far as the raw record can.
    function New-PositiveRecord([string]$Id, [object[]]$Conditions) {
        $Record = [ordered]@{ Id = $Id; Operation = 'Unset'; UserId = 'user@contoso.com'; ResultStatus = 'Success'; Workload = 'AzureActiveDirectory'; ClientIP = '185.1.2.3' }
        $Parameters = [System.Collections.Generic.List[object]]::new()
        foreach ($Condition in $Conditions) {
            $Label = $Condition.Property.label
            $Operator = ([string]$Condition.Operator.value).ToLower()
            $Value = @($Condition.Input.value)[0]
            $Text = switch ($Operator) {
                'like' { ([string]$Value) -replace '[*?]', 'x' }
                { $_ -in 'notlike', 'ne', 'notin', 'notmatch' } { 'zz-other@contoso.com' }
                default { [string]$Value }
            }
            switch -Regex ($Label) {
                '^CIPPAddedKeyTypes$' {
                    $Type = ([string]$Value).Trim('*')
                    $Record.ModifiedProperties = @(@{ Name = 'KeyDescription'; OldValue = '[]'; NewValue = "[[KeyIdentifier=k1,KeyType=$Type,KeyUsage=Verify,DisplayName=new]]" })
                }
                '^CIPPActor$' { $Record.Actor = @(@{ ID = $Text; Type = 1 }) }
                '^CIPPActor(IsTarget|Type)$' { $Record.Actor = @(@{ ID = 'ServicePrincipal_self-1'; Type = 2 }); $Record.Target = @(@{ ID = 'ServicePrincipal_self-1'; Type = 2 }) }
                '^CIPP' { }
                '^(Operation|UserId|ResultStatus|Workload|ObjectId)$' { $Record[$Label] = $Text }
                default { $Parameters.Add(@{ Name = $Label; Value = $Text }) }
            }
        }
        if ($Parameters.Count) { $Record.Parameters = $Parameters.ToArray() }
        $Record
    }

    # Every preset's positive record, the same with an unrelated operation, and some everyday traffic.
    $script:PresetCorpus = [System.Collections.Generic.List[object]]::new()
    $script:PresetConditions = @{}
    $Templates = Get-Content -Raw (Join-Path (Split-Path -Parent $RepoRoot) 'frontend/src/data/AuditLogTemplates.json') | ConvertFrom-Json
    foreach ($Template in $Templates) {
        $script:PresetConditions[$Template.value] = @($Template.template.conditions)
        $Positive = New-PositiveRecord "$($Template.value)-hit" @($Template.template.conditions)
        $script:PresetCorpus.Add($Positive)
        $Miss = [ordered]@{}; foreach ($Key in $Positive.Keys) { $Miss[$Key] = $Positive[$Key] }
        $Miss.Id = "$($Template.value)-miss"; $Miss.Operation = 'Unrelated-Operation'
        $script:PresetCorpus.Add($Miss)
        if ($Positive.UserId -like 'ServicePrincipal_*') {
            $Flip = [ordered]@{}; foreach ($Key in $Positive.Keys) { $Flip[$Key] = $Positive[$Key] }
            $Flip.Id = "$($Template.value)-user"; $Flip.UserId = 'admin@contoso.com'
            $script:PresetCorpus.Add($Flip)
        }
    }
    foreach ($Operation in 'UserLoggedIn', 'MailItemsAccessed', 'Set-Mailbox', 'Send') { $script:PresetCorpus.Add([ordered]@{ Id = "plain-$Operation"; Operation = $Operation; UserId = 'user@contoso.com'; ResultStatus = 'Success'; ClientIP = '203.0.113.9' }) }
}

Describe 'Get-CIPPAuditLogPrefilter against the engine: every preset on its own' {
    It 'never drops a record <Name> matches' -ForEach $script:Presets {
        $Comparison = Compare-Prefilter -Rules (, $Conditions) -Records $script:PresetCorpus
        Assert-NoMissed $Comparison
        if ($null -ne $Comparison.Prefilter) {
            $Comparison.Kept | Should -Not -Contain "$Name-miss" -Because 'an unrelated operation can match no preset'
            $Comparison.Kept | Should -Not -Contain 'plain-MailItemsAccessed'
        }
    }

    It 'matches its own positive record for <Name> when every condition can be shaped from the raw record' -ForEach @($script:Presets.Where({ -not @($_.Conditions.Property.label -match '^(CIPPGeoLocation|CIPPBadRepIP|CIPPHostedIP)$').Count })) {
        $Comparison = Compare-Prefilter -Rules (, $Conditions) -Records $script:PresetCorpus
        $Comparison.Matched | Should -Contain "$Name-hit"
        $Comparison.Kept | Should -Contain "$Name-hit"
    }
}

Describe 'Get-CIPPAuditLogPrefilter against the engine: every preset at once' {
    It 'keeps every record any of the presets matches, as one rule set over the same logs' {
        $Comparison = Compare-Prefilter -Rules @($script:Presets | ForEach-Object { , @($_.Conditions) }) -Records $script:PresetCorpus
        Assert-NoMissed $Comparison
    }

    It 'keeps every record any of the non-geo presets matches, and drops traffic none of them can match' {
        $Rules = @($script:Presets.Where({ -not @($_.Conditions.Property.label -eq 'CIPPGeoLocation').Count }) | ForEach-Object { , @($_.Conditions) })
        $Comparison = Compare-Prefilter -Rules $Rules -Records $script:PresetCorpus
        Assert-NoMissed $Comparison
        $Comparison.Kept | Should -Not -Contain 'plain-MailItemsAccessed'
        @($Comparison.Kept.Where({ $_ -like '*-miss' })) | Should -BeNullOrEmpty
    }
}

Describe 'Get-CIPPAuditLogPrefilter against the engine: every operator' {
    BeforeAll {
        $script:OperatorCorpus = @(
            [ordered]@{ Id = 'a'; Operation = 'New-InboxRule'; UserId = 'ServicePrincipal_1'; ResultStatus = 'Success' }
            [ordered]@{ Id = 'b'; Operation = 'Set-InboxRule'; UserId = 'admin@contoso.com'; ResultStatus = 'Failed' }
            [ordered]@{ Id = 'c'; Operation = "New-InboxRule$([char]0x200B)"; UserId = 'ADMIN@CONTOSO.COM'; ResultStatus = 'success' }
            [ordered]@{ Id = 'd'; Operation = 'UserLoggedIn'; UserId = 'user@contoso.com'; ResultStatus = 'Success' }
            [ordered]@{ Id = 'e'; Operation = 'Add member to role.'; ResultStatus = 'Success' }
        )
    }

    It '<Property> <Operator> <Value> keeps exactly what the engine matches' -ForEach @(
        foreach ($Case in @(
                @{ Operator = 'eq'; Value = 'new-inboxrule' }, @{ Operator = 'ne'; Value = 'New-InboxRule' }
                @{ Operator = 'like'; Value = '*inboxrule*' }, @{ Operator = 'notlike'; Value = 'New-*' }
                @{ Operator = 'match'; Value = '^[NS]e[wt]-' }, @{ Operator = 'notmatch'; Value = 'inbox' }
                @{ Operator = 'gt'; Value = 'Set' }, @{ Operator = 'lt'; Value = 'Set' }, @{ Operator = 'ge'; Value = 'Set-InboxRule' }, @{ Operator = 'le'; Value = 'Set-InboxRule' }
                @{ Operator = 'in'; Value = @('New-InboxRule', 'UserLoggedIn') }, @{ Operator = 'notin'; Value = @('New-InboxRule', 'UserLoggedIn') }
                @{ Operator = 'contains'; Value = 'UserLoggedIn' }, @{ Operator = 'notcontains'; Value = 'UserLoggedIn' }
            )) {
            foreach ($Property in 'Operation', 'UserId', 'ResultStatus') { @{ Property = $Property; Operator = $Case.Operator; Value = $Case.Value } }
        }
    ) {
        # A condition that is not an anchor itself is paired with one every record satisfies, or the engine skips the rule.
        $Conditions = @(New-Condition $Property $Operator $Value)
        if ($Property -ne 'Operation' -or $Operator -notin 'eq', 'in', 'like') { $Conditions = @((New-Condition 'Operation' 'in' @($script:OperatorCorpus.Operation)), $Conditions[0]) }
        $Comparison = Compare-Prefilter -Rules (, $Conditions) -Records $script:OperatorCorpus
        ($Comparison.Kept -join ',') | Should -Be ($Comparison.Matched -join ',')
    }

    It 'treats an upper-case operator as the engine does' {
        $Comparison = Compare-Prefilter -Rules (, @(New-Condition 'Operation' 'EQ' 'UserLoggedIn')) -Records $script:OperatorCorpus
        $Comparison.Kept | Should -Be @('d')
        $Comparison.Matched | Should -Be @('d')
    }
}

Describe 'Get-CIPPAuditLogPrefilter against the engine: names the engine derives or flattens' {
    BeforeAll {
        $script:ShapedCorpus = @(
            [ordered]@{ Id = 's1'; Operation = 'UserLoggedIn'; UserId = 'u@contoso.com'; ClientIP = '185.1.2.3:443'; ExtendedProperties = @(@{ Name = 'UserAgent'; Value = 'curl/8' }); DeviceProperties = @(@{ Name = 'OS'; Value = 'Linux' }) }
            [ordered]@{ Id = 's2'; Operation = 'UserLoggedIn'; UserId = 'u@contoso.com'; ClientIP = '10.0.0.5'; ExtendedProperties = @(@{ Name = 'UserAgent'; Value = 'Edge' }) }
            [ordered]@{ Id = 's3'; Operation = 'Set-Mailbox'; UserId = 'u@contoso.com'; ModifiedProperties = @(@{ Name = 'ModProp'; NewValue = 'new'; OldValue = 'old' }) }
            [ordered]@{ Id = 's4'; Operation = 'Send'; UserId = 'u@contoso.com' }
        )
    }

    It 'keeps every anchored record when the other condition is on <Label>, which the raw record cannot answer' -ForEach @(
        @{ Label = 'CIPPGeoLocation'; Operator = 'notin'; Value = @('AU') }, @{ Label = 'CIPPUserKey'; Operator = 'eq'; Value = 'u@contoso.com' }
        @{ Label = 'clientip'; Operator = 'eq'; Value = '185.1.2.3' }, @{ Label = 'HasLocationData'; Operator = 'eq'; Value = 'True' }
        @{ Label = 'AuditRecord'; Operator = 'like'; Value = '*Send*' }, @{ Label = 'ExtendedProperties'; Operator = 'like'; Value = '*' }
        @{ Label = 'Previous_Value_ModProp'; Operator = 'eq'; Value = 'old' }, @{ Label = 'CIPPExtendedProperties'; Operator = 'like'; Value = '*curl*' }
    ) {
        $Comparison = Compare-Prefilter -Rules (, @((New-Condition 'Operation' 'in' @('UserLoggedIn', 'Set-Mailbox', 'Send')), (New-Condition $Label $Operator $Value))) -Records $script:ShapedCorpus
        $Comparison.Kept | Should -Be @('s1', 's2', 's3', 's4')
        Assert-NoMissed $Comparison
    }

    It 'tests a flattened name only on the records that carry it, and keeps those' {
        $Comparison = Compare-Prefilter -Rules (, @((New-Condition 'Operation' 'in' @('UserLoggedIn', 'Set-Mailbox', 'Send')), (New-Condition 'UserAgent' 'like' 'curl*'))) -Records $script:ShapedCorpus
        $Comparison.Matched | Should -Be @('s1')
        $Comparison.Kept | Should -Be @('s1', 's2')
    }

    It 'narrows by Operation while the other condition is on a derived name' {
        $Comparison = Compare-Prefilter -Rules (, @((New-Condition 'Operation' 'eq' 'UserLoggedIn'), (New-Condition 'CIPPGeoLocation' 'notin' @('AU')))) -Records $script:ShapedCorpus
        $Comparison.Kept | Should -Be @('s1', 's2')
        Assert-NoMissed $Comparison
    }
}

Describe 'Get-CIPPAuditLogPrefilter against the engine: a raw name a sub-object item overrides' {
    It 'keeps a record whose <Container> item named <Name> makes the engine see a different <Name>' -ForEach @(
        @{ Container = 'ExtendedProperties'; Name = 'Operation' }, @{ Container = 'DeviceProperties'; Name = 'Operation' }
        @{ Container = 'Parameters'; Name = 'Operation' }, @{ Container = 'ModifiedProperties'; Name = 'Operation' }
        @{ Container = 'Parameters'; Name = 'operation' }, @{ Container = 'ExtendedProperties'; Name = 'ResultStatus' }
    ) {
        $Item = if ($Container -eq 'ModifiedProperties') { @{ Name = $Name; NewValue = 'Target'; OldValue = 'x' } } else { @{ Name = $Name; Value = 'Target' } }
        $Shadowed = [ordered]@{ Id = 'shadowed'; Operation = 'Set-Mailbox'; ResultStatus = 'Success' }
        $Shadowed[$Container] = @($Item)
        $Plain = [ordered]@{ Id = 'plain'; Operation = 'Set-Mailbox'; ResultStatus = 'Success' }
        $Condition = New-Condition ($Name.Substring(0, 1).ToUpper() + $Name.Substring(1)) 'eq' 'Target'
        $Conditions = if ($Name -eq 'Operation') { @($Condition) } else { @((New-Condition 'Operation' 'eq' 'Set-Mailbox'), $Condition) }
        $Comparison = Compare-Prefilter -Rules (, $Conditions) -Records @($Shadowed, $Plain)
        $Comparison.Matched | Should -Be @('shadowed')
        $Comparison.Kept | Should -Be @('shadowed')
    }
}

Describe 'Get-CIPPAuditLogPrefilter against the engine: several rules over the same logs' {
    BeforeAll {
        $script:MultiCorpus = @(
            [ordered]@{ Id = 'only-a'; Operation = 'New-InboxRule'; ResultStatus = 'Failed'; UserId = 'admin@contoso.com' }
            [ordered]@{ Id = 'only-b'; Operation = 'New-InboxRule'; ResultStatus = 'Success'; UserId = 'ServicePrincipal_1' }
            [ordered]@{ Id = 'both'; Operation = 'New-InboxRule'; ResultStatus = 'Failed'; UserId = 'ServicePrincipal_2' }
            [ordered]@{ Id = 'neither'; Operation = 'New-InboxRule'; ResultStatus = 'Success'; UserId = 'admin@contoso.com' }
            [ordered]@{ Id = 'other-op'; Operation = 'Set-Mailbox'; ResultStatus = 'Failed'; UserId = 'ServicePrincipal_3' }
        )
        $script:RuleA = @((New-Condition 'Operation' 'eq' 'New-InboxRule'), (New-Condition 'ResultStatus' 'eq' 'Failed'))
        $script:RuleB = @((New-Condition 'Operation' 'in' @('New-InboxRule', 'Set-InboxRule')), (New-Condition 'UserId' 'like' 'ServicePrincipal_*'))
    }

    It 'keeps exactly the union of what each rule matches, <Shape> records' -ForEach @(@{ Shape = 'feed'; Graph = $false }, @{ Shape = 'Graph search'; Graph = $true }) {
        $Comparison = Compare-Prefilter -Rules @($script:RuleA, $script:RuleB) -Records $script:MultiCorpus -Graph:$Graph
        $Comparison.Matched | Should -Be @('both', 'only-a', 'only-b')
        ($Comparison.Kept -join ',') | Should -Be ($Comparison.Matched -join ',')
    }

    It 'ignores a rule the engine skips for an operator it rejects' {
        $Bogus = @(New-Condition 'Operation' 'bogus' 'Set-Mailbox')
        $Comparison = Compare-Prefilter -Rules @($script:RuleA, $Bogus) -Records $script:MultiCorpus
        ($Comparison.Kept -join ',') | Should -Be ($Comparison.Matched -join ',')
        $Comparison.Kept | Should -Be @('both', 'only-a')
    }

    It 'ignores a rule that excludes the tenant' {
        $Comparison = Compare-Prefilter -Rules @($script:RuleA, $script:RuleB) -Records $script:MultiCorpus -Excluded 'rule-2'
        $Comparison.Kept | Should -Be @('both', 'only-a')
        ($Comparison.Kept -join ',') | Should -Be ($Comparison.Matched -join ',')
    }

    It 'ignores a rule with only empty conditions' {
        $Comparison = Compare-Prefilter -Rules @($script:RuleA, @(New-Condition 'Operation' 'eq' '')) -Records $script:MultiCorpus
        $Comparison.Kept | Should -Be @('both', 'only-a')
    }

    It 'skips a rule without an anchor, as the engine does' {
        $Comparison = Compare-Prefilter -Rules @($script:RuleA, @(New-Condition 'CIPPGeoLocation' 'notin' @('AU')), @(New-Condition 'Operation' 'like' '*-*')) -Records $script:MultiCorpus
        $Comparison.Prefilter.Rules.Count | Should -Be 1
        $Comparison.Kept | Should -Be @('both', 'only-a')
        ($Comparison.Kept -join ',') | Should -Be ($Comparison.Matched -join ',')
    }

    It 'keeps a record a rule throws on, where the engine matches nothing for that rule' {
        $Comparison = Compare-Prefilter -Rules @(, @((New-Condition 'Operation' 'eq' 'X'), (New-Condition 'ResultStatus' 'gt' 5))) -Records @([ordered]@{ Id = 'odd'; Operation = 'X'; ResultStatus = [datetime]'2026-01-01' })
        Assert-NoMissed $Comparison
        $Comparison.Kept | Should -Be @('odd')
    }

    It 'gives the blob check the needles of every rule it keeps' {
        Set-Rules @($script:RuleA, $script:RuleB, @(New-Condition 'UserId' 'like' 'ServicePrincipal_*'))
        $script:AuditRuleSetCache = $null
        @((Get-CIPPAuditLogPrefilter -TenantFilter 'contoso.com').Needles | Sort-Object) | Should -Be @('"Operation":"New-InboxRule', '"Operation":"Set-InboxRule')
        Set-Rules @(, @(New-Condition 'UserId' 'like' 'ServicePrincipal_*'))
        $script:AuditRuleSetCache = $null
        $Prefilter = Get-CIPPAuditLogPrefilter -TenantFilter 'contoso.com'
        $Prefilter | Should -Not -BeNullOrEmpty
        $Prefilter.Needles.Count | Should -Be 0
    }

    It 'runs a record only through the rules its Operation can satisfy (eq, in, like, any case)' {
        $Like = @((New-Condition 'Operation' 'like' 'Add member to*'), (New-Condition 'ResultStatus' 'eq' 'Failed'))
        $NoOperation = @(New-Condition 'UserId' 'like' 'ServicePrincipal_*')
        Set-Rules @($script:RuleA, $script:RuleB, $Like, $NoOperation)
        $script:AuditRuleSetCache = $null
        $Prefilter = Get-CIPPAuditLogPrefilter -TenantFilter 'contoso.com'
        $Records = @(ConvertTo-Records @(
                [ordered]@{ Id = '1'; Operation = 'new-inboxrule'; ResultStatus = 'Success'; UserId = 'a' }
                [ordered]@{ Id = '2'; Operation = 'Set-InboxRule'; ResultStatus = 'Success'; UserId = 'a' }
                [ordered]@{ Id = '3'; Operation = 'Add member to role.'; ResultStatus = 'Success'; UserId = 'a' }
                [ordered]@{ Id = '4'; Operation = 'Update user.'; ResultStatus = 'Success'; UserId = 'a' }
            ))
        $null = Select-CIPPAuditLogCandidate -Prefilter $Prefilter -Records $Records
        $Rules = $Prefilter.Rules
        $Rules.Count | Should -Be 3
        $Prefilter.ByOperation['New-InboxRule'] | Should -Be @($Rules[0], $Rules[1])
        $Prefilter.ByOperation['Set-InboxRule'] | Should -Be @($Rules[1])
        $Prefilter.ByOperation['Add member to role.'] | Should -Be @($Rules[2])
        $Prefilter.ByOperation['Update user.'].Count | Should -Be 0
    }

    It 'keeps exactly what running every rule on every record keeps, over every preset at once' {
        Set-Rules @($script:PresetConditions.Values | ForEach-Object { , @($_) })
        $script:AuditRuleSetCache = $null
        $Indexed = Get-CIPPAuditLogPrefilter -TenantFilter 'contoso.com'
        $Unindexed = [pscustomobject]@{ Rules = $Indexed.Rules }
        $Records = @(ConvertTo-Records $script:PresetCorpus)
        $Kept = @(Select-CIPPAuditLogCandidate -Prefilter $Indexed -Records $Records).Id
        $Kept | Should -Not -BeNullOrEmpty
        $Kept | Should -Be @(Select-CIPPAuditLogCandidate -Prefilter $Unindexed -Records $Records).Id
    }
}

Describe 'Test-CIPPAuditLogRules -EvaluateOnly' {
    It 'matches what the full engine matches, without claims, alerts or cache writes' {
        $Rules = @(, @(New-Condition 'Operation' 'eq' 'New-InboxRule'))
        $Records = @([ordered]@{ Id = 'r1'; Operation = 'New-InboxRule' }, [ordered]@{ Id = 'r2'; Operation = 'Set-Mailbox' })
        $Full = Compare-Prefilter -Rules $Rules -Records $Records
        Mock Invoke-CippWebhookProcessing {}
        Mock Add-AzDataTableEntity {}
        Mock Remove-AzDataTableEntity {}
        Mock Remove-CIPPAzDataTableEntity {}
        Mock Get-AzDataTableEntity {}
        $script:AuditRuleSetCache = $null
        $Result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(ConvertTo-Records $Records) -EvaluateOnly 3>$null 6>$null
        @(@($Result.DataToProcess).Id) | Should -Be $Full.Matched
        $Result.Error | Should -BeNullOrEmpty
        @($Result.DataToProcess)[0].AuditRecord | Should -BeOfType [string]
        Should -Invoke Invoke-CippWebhookProcessing -Times 0 -Exactly
        Should -Invoke Add-AzDataTableEntity -Times 0 -Exactly
        Should -Invoke Remove-AzDataTableEntity -Times 0 -Exactly
        Should -Invoke Remove-CIPPAzDataTableEntity -Times 0 -Exactly
        Should -Invoke Get-AzDataTableEntity -Times 0 -Exactly
    }

    It 'compiles the rules once per rule set and exclusion list, and again when either is reloaded' {
        foreach ($Name in 'AuditRuleSetCache', 'AuditRuleSearchLookups', 'AuditRuleListCache', 'AuditRuleClauseCache') { Set-Variable -Scope Script -Name $Name -Value $null }
        $Records = @([ordered]@{ Id = 'r1'; Operation = 'New-InboxRule' }, [ordered]@{ Id = 'r2'; Operation = 'Set-Mailbox' })
        Set-Rules @(, @(New-Condition 'Operation' 'eq' 'New-InboxRule'))
        $First = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(ConvertTo-Records $Records) -EvaluateOnly 3>$null 6>$null
        $Compiled = $script:AuditRuleClauseCache['contoso.com']
        $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(ConvertTo-Records $Records) -EvaluateOnly 3>$null 6>$null
        [object]::ReferenceEquals($script:AuditRuleClauseCache['contoso.com'], $Compiled) | Should -BeTrue
        # An edited rule arrives with the next rule set; new exclusions with the next list read.
        Set-Rules @(, @(New-Condition 'Operation' 'eq' 'Set-Mailbox'))
        $script:AuditRuleSetCache = $null
        $Edited = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(ConvertTo-Records $Records) -EvaluateOnly 3>$null 6>$null
        $Recompiled = $script:AuditRuleClauseCache['contoso.com']
        $script:AuditRuleListCache = $null
        $null = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(ConvertTo-Records $Records) -EvaluateOnly 3>$null 6>$null
        @(@($First.DataToProcess).Id) | Should -Be @('r1')
        @(@($Edited.DataToProcess).Id) | Should -Be @('r2')
        [object]::ReferenceEquals($Recompiled, $Compiled) | Should -BeFalse
        [object]::ReferenceEquals($script:AuditRuleClauseCache['contoso.com'], $Recompiled) | Should -BeFalse
    }

    It 'alerts on a record once, for the first rule it matches, and skips a rule without an anchor' {
        foreach ($Name in 'AuditRuleSetCache', 'AuditRuleSearchLookups', 'AuditRuleListCache', 'AuditRuleClauseCache') { Set-Variable -Scope Script -Name $Name -Value $null }
        Set-Rules @(
            @((New-Condition 'Operation' 'eq' 'New-InboxRule'), (New-Condition 'ResultStatus' 'eq' 'Failed')),
            @(, (New-Condition 'Operation' 'like' 'New-Inbox*')),
            @(, (New-Condition 'UserId' 'eq' 'u@contoso.com'))
        )
        $Records = @(
            [ordered]@{ Id = 'both'; Operation = 'New-InboxRule'; ResultStatus = 'Failed'; UserId = 'u@contoso.com' }
            [ordered]@{ Id = 'second'; Operation = 'New-InboxRule'; ResultStatus = 'Success'; UserId = 'u@contoso.com' }
            [ordered]@{ Id = 'unanchored'; Operation = 'Set-Mailbox'; UserId = 'u@contoso.com' }
        )
        $Result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(ConvertTo-Records $Records) -EvaluateOnly 3>$null 6>$null
        @($Result.DataToProcess).Id | Should -Be @('both', 'second')
        @($Result.DataToProcess).CIPPClause | Should -Be @('Operation is eq New-InboxRule and ResultStatus is eq Failed', 'Operation is like New-Inbox*')
    }
}

Describe 'Test-CIPPAuditLogRules -EvaluateOnly directory load' {
    It 'reads the directory only when a rule names a mapped CIPP field (<CippField>), with the same matches either way' -ForEach @(
        @{ CippField = ''; Reads = 0 }
        @{ CippField = 'CIPPUserId'; Reads = 1 }
        @{ CippField = 'CIPPActor'; Reads = 0 }
        @{ CippField = 'CIPPActorType'; Reads = 0 }
        @{ CippField = 'CIPPAddedKeys'; Reads = 0 }
        @{ CippField = 'CIPPGeoLocation'; Reads = 0 }
    ) {
        $Conditions = @(New-Condition 'Operation' 'eq' 'Set-Mailbox')
        if ($CippField) { $Conditions = @($Conditions[0], (New-Condition $CippField 'like' '*')) }
        $Rule = @(, $Conditions)
        $Records = @([ordered]@{ Id = 'r1'; Operation = 'Set-Mailbox'; UserId = '11111111-2222-3333-4444-555555555555' }, [ordered]@{ Id = 'r2'; Operation = 'Send' })
        $Full = Compare-Prefilter -Rules $Rule -Records $Records
        $script:DirectoryReads = 0
        $script:AuditRuleSetCache = $null
        $script:AuditRuleSearchLookups = $null
        $Result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(ConvertTo-Records $Records) -EvaluateOnly 3>$null 6>$null
        $script:DirectoryReads | Should -Be $Reads
        (@(@($Result.DataToProcess).Id | Sort-Object -Unique) -join ',') | Should -Be ($Full.Matched -join ',')
    }
}

Describe 'Test-CIPPAuditLogRules actor and target fields' {
    BeforeAll {
        # The shapes Entra writes: Type 1 display names, Type 2 ids and type words, Type 4 object ids, Type 5 UPNs.
        function New-AppRecord([string]$Id, [object[]]$Actor, [object[]]$Target) {
            [ordered]@{ Id = $Id; Operation = 'Add app role assignment to service principal.'; ActorContextId = 'tenant-1'; TargetContextId = 'tenant-1'; Actor = $Actor; Target = $Target }
        }
        $SamActor = @(@{ ID = 'CIPP-SAM'; Type = 1 }, @{ ID = 'appid-1'; Type = 2 }, @{ ID = 'ServicePrincipal_sp-1'; Type = 2 }, @{ ID = 'sp-1'; Type = 2 }, @{ ID = 'ServicePrincipal'; Type = 2 }, @{ ID = 'NotAgentic'; Type = 2 })
        $script:ActorCorpus = @(
            New-AppRecord 'self-sp' $SamActor @(@{ ID = 'ServicePrincipal_sp-1'; Type = 2 }, @{ ID = 'sp-1'; Type = 2 }, @{ ID = 'ServicePrincipal'; Type = 2 }, @{ ID = 'Microsoft Graph'; Type = 1 }, @{ ID = 'tenant-1'; Type = 2 })
            New-AppRecord 'self-app' $SamActor @(@{ ID = 'Application_app-obj-1'; Type = 2 }, @{ ID = 'app-obj-1'; Type = 2 }, @{ ID = 'Application'; Type = 2 }, @{ ID = 'appid-1'; Type = 2 })
            New-AppRecord 'other-sp' $SamActor @(@{ ID = 'ServicePrincipal_sp-2'; Type = 2 }, @{ ID = 'sp-2'; Type = 2 }, @{ ID = 'ServicePrincipal'; Type = 2 }, @{ ID = 'tenant-1'; Type = 2 })
            New-AppRecord 'tenant-only' @(@{ ID = 'ServicePrincipal_sp-1'; Type = 2 }, @{ ID = 'tenant-1'; Type = 2 }) @(@{ ID = 'ServicePrincipal_sp-3'; Type = 2 }, @{ ID = 'tenant-1'; Type = 2 })
            New-AppRecord 'same-name' @(@{ ID = 'Shared Name'; Type = 1 }, @{ ID = 'User_u-1'; Type = 2 }, @{ ID = 'User'; Type = 2 }) @(@{ ID = 'Shared Name'; Type = 1 }, @{ ID = 'User_u-2'; Type = 2 }, @{ ID = 'User'; Type = 2 })
            New-AppRecord 'user-self' @(@{ ID = 'User_u-1'; Type = 2 }, @{ ID = 'u1@contoso.com'; Type = 5 }) @(@{ ID = 'User_u-1'; Type = 2 })
            [ordered]@{ Id = 'no-actor'; Operation = 'Add app role assignment to service principal.' }
        )
    }

    It 'CIPPActorIsTarget eq <Value> matches <Expected>' -ForEach @(
        @{ Value = 'True'; Expected = @('self-app', 'self-sp', 'user-self') }
        @{ Value = 'False'; Expected = @('no-actor', 'other-sp', 'same-name', 'tenant-only') }
    ) {
        $Comparison = Compare-Prefilter -Rules (, @((New-Condition 'Operation' 'eq' 'Add app role assignment to service principal.'), (New-Condition 'CIPPActorIsTarget' 'eq' $Value))) -Records $script:ActorCorpus
        ($Comparison.Matched -join ',') | Should -Be (($Expected | Sort-Object) -join ',')
        Assert-NoMissed $Comparison
    }

    It 'derives CIPPActorType and CIPPTargetType from the prefixed ids' {
        $Comparison = Compare-Prefilter -Rules (, @((New-Condition 'Operation' 'eq' 'Add app role assignment to service principal.'), (New-Condition 'CIPPActorType' 'eq' 'ServicePrincipal'), (New-Condition 'CIPPTargetType' 'eq' 'Application'))) -Records $script:ActorCorpus
        $Comparison.Matched | Should -Be @('self-app')
        Assert-NoMissed $Comparison
    }

    It 'leaves the fields off when no rule names them' {
        Set-Rules @(, @(New-Condition 'Operation' 'eq' 'Add app role assignment to service principal.'))
        $script:AuditRuleSetCache = $null
        $Result = Test-CIPPAuditLogRules -TenantFilter 'contoso.com' -Rows @(ConvertTo-Records $script:ActorCorpus) -EvaluateOnly 3>$null 6>$null
        @($Result.DataToProcess)[0].PSObject.Properties.Name | Should -Not -Contain 'CIPPActorIsTarget'
        @($Result.DataToProcess)[0].PSObject.Properties.Name | Should -Not -Contain 'CIPPActor'
    }

    It 'joins the actor ids into CIPPActor when a rule names it' {
        $Comparison = Compare-Prefilter -Rules (, @((New-Condition 'Operation' 'eq' 'Add app role assignment to service principal.'), (New-Condition 'CIPPActor' 'like' '*u1@contoso.com*'))) -Records $script:ActorCorpus
        $Comparison.Matched | Should -Be @('user-self')
        Assert-NoMissed $Comparison
    }

    It 'CIPPActor <Operator> <Value> keeps exactly what the engine matches' -ForEach @(
        @{ Operator = 'like'; Value = '*u1@contoso.com*' }, @{ Operator = 'notlike'; Value = '*ServicePrincipal_sp-1*' }
        @{ Operator = 'eq'; Value = 'User_u-1, u1@contoso.com' }, @{ Operator = 'ne'; Value = 'User_u-1, u1@contoso.com' }
        @{ Operator = 'match'; Value = 'Shared Name' }, @{ Operator = 'in'; Value = @('User_u-1, u1@contoso.com', 'x') }
    ) {
        $Comparison = Compare-Prefilter -Rules (, @((New-Condition 'Operation' 'eq' 'Add app role assignment to service principal.'), (New-Condition 'CIPPActor' $Operator $Value))) -Records $script:ActorCorpus
        ($Comparison.Kept -join ',') | Should -Be ($Comparison.Matched -join ',')
    }

    It 'keeps a record whose flattened properties shadow CIPPActor' {
        $Records = @([ordered]@{ Id = 'flat'; Operation = 'Op'; ExtendedProperties = @(@{ Name = 'CIPPActor'; Value = 'MS-PIM' }) })
        $Comparison = Compare-Prefilter -Rules (, @((New-Condition 'Operation' 'eq' 'Op'), (New-Condition 'CIPPActor' 'like' '*MS-PIM*'))) -Records $Records
        Assert-NoMissed $Comparison
        $Comparison.Kept | Should -Be @('flat')
    }

    It 'the AppGrantedItselfAccess preset alerts only on a service principal granting itself access' {
        $Preset = $script:PresetConditions['AppGrantedItselfAccess']
        $Comparison = Compare-Prefilter -Rules (, $Preset) -Records $script:ActorCorpus
        $Comparison.Matched | Should -Be @('self-app', 'self-sp')
        Assert-NoMissed $Comparison
    }
}
