# Pins what counts as an audit log rule's anchor, and that Invoke-AddAlert refuses a rule without one.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $env:CIPPRootPath = $RepoRoot
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Get-CIPPAuditLogRuleAnchor.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Split-CIPPAuditLogConditions.ps1')

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }
    function Get-CippTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Context, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Context, $Entity, [switch]$Force) }
    function Write-LogMessage { param($API, $tenant, $message, $sev, $LogData, $headers) }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules/CIPPHTTP') -Recurse -Filter 'Invoke-AddAlert.ps1' -File)[0].FullName

    # The shapes the alert form posts: Input is one {value} object, or an array of them for In.
    function New-Condition([string]$Property, [string]$Operator, $Value) {
        $InputValue = if ($Value -is [array]) { @(foreach ($Item in $Value) { @{ value = $Item; label = $Item } }) } else { @{ value = $Value; label = $Value } }
        [pscustomobject]@{ Property = @{ label = $Property; value = 'String' }; Operator = @{ label = $Operator; value = $Operator }; Input = $InputValue }
    }
}

Describe 'Get-CIPPAuditLogRuleAnchor' {
    It 'anchors on <Operator> <Value> with needle <Needle>' -ForEach @(
        @{ Operator = 'EQ'; Value = 'New-InboxRule'; Needle = '"Operation":"New-InboxRule' }
        @{ Operator = 'eq'; Value = 'Op'; Needle = '"Operation":"Op' }
        @{ Operator = 'like'; Value = 'Update application*Certificates*'; Needle = '"Operation":"Update application' }
        @{ Operator = 'like'; Value = '*application*Certificates and secrets management*'; Needle = 'Certificates and secrets management' }
        @{ Operator = 'eq'; Value = "Update application $([char]0x2013) Certificates"; Needle = '"Operation":"Update application ' }
        @{ Operator = 'eq'; Value = "$([char]0x2013)$([char]0x2013) secrets"; Needle = ' secrets' }
    ) {
        $Anchor = Get-CIPPAuditLogRuleAnchor -Conditions @(New-Condition 'Operation' $Operator $Value)
        $Anchor.Needles | Should -Be @($Needle)
        if ($Operator -eq 'like') { $Anchor.Patterns[0].IsMatch($Value.Replace('*', 'x')) | Should -BeTrue } else { $Anchor.Literals.Contains($Value.ToUpper()) | Should -BeTrue }
    }

    It 'anchors on In with a literal and a needle per value' {
        $Anchor = Get-CIPPAuditLogRuleAnchor -Conditions @((New-Condition 'UserId' 'eq' 'x'), (New-Condition 'Operation' 'in' @('Add owner to application.', 'Add owner to service principal.')))
        @($Anchor.Literals) | Sort-Object | Should -Be @('Add owner to application.', 'Add owner to service principal.')
        @($Anchor.Needles) | Sort-Object | Should -Be @('"Operation":"Add owner to application.', '"Operation":"Add owner to service principal.')
    }

    It 'gives no anchor for <Case>' -ForEach @(
        @{ Case = 'no Operation condition'; Conditions = @(@{ P = 'UserId'; O = 'like'; V = 'ServicePrincipal_*' }) }
        @{ Case = 'Operation ne'; Conditions = @(@{ P = 'Operation'; O = 'ne'; V = 'Send' }) }
        @{ Case = 'Operation notin'; Conditions = @(@{ P = 'Operation'; O = 'notin'; V = @('Send', 'MailItemsAccessed') }) }
        @{ Case = 'Operation match'; Conditions = @(@{ P = 'Operation'; O = 'match'; V = 'Inbox' }) }
        @{ Case = 'a like with no text'; Conditions = @(@{ P = 'Operation'; O = 'like'; V = '*' }) }
        @{ Case = 'a like with under three characters of text'; Conditions = @(@{ P = 'Operation'; O = 'like'; V = '*-*' }) }
        @{ Case = 'an empty value'; Conditions = @(@{ P = 'Operation'; O = 'eq'; V = '' }) }
        @{ Case = 'a like with one value that cannot anchor'; Conditions = @(@{ P = 'Operation'; O = 'like'; V = @('New-InboxRule', '*') }) }
    ) {
        Get-CIPPAuditLogRuleAnchor -Conditions @(foreach ($C in $Conditions) { New-Condition $C.P $C.O $C.V }) | Should -BeNullOrEmpty
    }

    It 'uses the first Operation condition that anchors' {
        $Anchor = Get-CIPPAuditLogRuleAnchor -Conditions @((New-Condition 'Operation' 'ne' 'Send'), (New-Condition 'Operation' 'eq' 'Set-Mailbox'))
        $Anchor.Needles | Should -Be @('"Operation":"Set-Mailbox')
    }

    It 'anchors every preset' {
        $Templates = Get-Content -Raw (Join-Path (Split-Path -Parent $RepoRoot) 'frontend/src/data/AuditLogTemplates.json') | ConvertFrom-Json
        @($Templates.Where({ $null -eq (Get-CIPPAuditLogRuleAnchor -Conditions $_.template.conditions) }).value) | Should -BeNullOrEmpty
    }
}

Describe 'Split-CIPPAuditLogConditions' {
    It 'keeps an alert without groups as one group' {
        $Groups = @(Split-CIPPAuditLogConditions -Conditions @((New-Condition 'Operation' 'eq' 'A'), (New-Condition 'UserId' 'eq' 'x')))
        $Groups | Should -HaveCount 1
        $Groups[0].Conditions | Should -HaveCount 2
    }

    It 'splits by Group in order and adds the conditions for every group to each' {
        $Conditions = @(
            (New-Condition 'Operation' 'eq' 'B') | Add-Member -NotePropertyName Group -NotePropertyValue 2 -PassThru
            (New-Condition 'UserId' 'notlike' 'bob@*') | Add-Member -NotePropertyName Group -NotePropertyValue -1 -PassThru
            (New-Condition 'Operation' 'eq' 'A')
        )
        $Groups = @(Split-CIPPAuditLogConditions -Conditions $Conditions)
        $Groups.Group | Should -Be @(0, 2)
        $Groups[0].Conditions.Input.value | Should -Be @('A', 'bob@*')
        $Groups[1].Conditions.Input.value | Should -Be @('B', 'bob@*')
    }
}

Describe 'Invoke-AddAlert' {
    BeforeEach { Mock Add-CIPPAzDataTableEntity {} }

    It 'refuses a rule without an anchor, saving nothing' {
        $Response = Invoke-AddAlert -Request ([pscustomobject]@{ Body = [pscustomobject]@{ conditions = @(New-Condition 'UserId' 'like' 'ServicePrincipal_*') } })
        $Response.StatusCode | Should -Be 400
        $Response.Body.error | Should -BeLike '*Operation condition*'
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'saves a rule with an anchor' {
        $Response = Invoke-AddAlert -Request ([pscustomobject]@{ Body = [pscustomobject]@{ conditions = @(New-Condition 'Operation' 'eq' 'New-InboxRule'); tenantFilter = @(@{ value = 'AllTenants' }); logbook = @{ value = 'Audit.Exchange' } } })
        $Response.StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly
    }

    It 'refuses a log source that is not a feed content type' {
        $Response = Invoke-AddAlert -Request ([pscustomobject]@{ Body = [pscustomobject]@{ conditions = @(New-Condition 'Operation' 'eq' 'FileDeleted'); logbook = @{ value = 'Audit.Teams' } } })
        $Response.StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'saves a SharePoint threshold rule with its count and window' {
        $Response = Invoke-AddAlert -Request ([pscustomobject]@{ Body = [pscustomobject]@{ conditions = @(New-Condition 'Operation' 'in' @('FileDeleted', 'FileRecycled')); tenantFilter = @(@{ value = 'AllTenants' }); logbook = @{ value = 'Audit.SharePoint' }; thresholdEnabled = $true; threshold = @{ Count = '100'; Minutes = '20' } } })
        $Response.StatusCode | Should -Be 200
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $Entity.type -eq 'Audit.SharePoint' -and $Entity.Threshold -eq '{"Count":100,"Minutes":20}' }
    }

    It 'refuses a threshold of <Case>' -ForEach @(
        @{ Case = 'a count below 2'; Op = 'eq'; Value = 'FileDeleted'; Threshold = @{ Count = 1; Minutes = 20 } }
        @{ Case = 'a window under 10 minutes'; Op = 'eq'; Value = 'FileDeleted'; Threshold = @{ Count = 50; Minutes = 5 } }
        @{ Case = 'a Like anchor'; Op = 'like'; Value = 'File*'; Threshold = @{ Count = 50; Minutes = 20 } }
    ) {
        $Response = Invoke-AddAlert -Request ([pscustomobject]@{ Body = [pscustomobject]@{ conditions = @(New-Condition 'Operation' $Op $Value); logbook = @{ value = 'Audit.SharePoint' }; thresholdEnabled = $true; threshold = $Threshold } })
        $Response.StatusCode | Should -Be 400
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'saves OR groups that each name their operations' {
        $Conditions = @(
            (New-Condition 'Operation' 'eq' 'New-InboxRule'), (New-Condition 'ForwardTo' 'like' '*@*')
            (New-Condition 'Operation' 'eq' 'Set-Mailbox') | Add-Member -NotePropertyName Group -NotePropertyValue 1 -PassThru
        )
        $Response = Invoke-AddAlert -Request ([pscustomobject]@{ Body = [pscustomobject]@{ conditions = $Conditions; tenantFilter = @(@{ value = 'AllTenants' }); logbook = @{ value = 'Audit.Exchange' } } })
        $Response.StatusCode | Should -Be 200
    }

    It 'refuses <Case>' -ForEach @(
        @{ Case = 'two Operation conditions in one group'; Second = 'Operation'; Group = 0; Error = '*only one Operation condition*' }
        @{ Case = 'a group without an Operation condition'; Second = 'UserId'; Group = 1; Error = '*Each group of conditions needs an Operation condition*' }
    ) {
        $Conditions = @(
            (New-Condition 'Operation' 'eq' 'New-InboxRule')
            (New-Condition $Second 'eq' 'Set-Mailbox') | Add-Member -NotePropertyName Group -NotePropertyValue $Group -PassThru
        )
        $Response = Invoke-AddAlert -Request ([pscustomobject]@{ Body = [pscustomobject]@{ conditions = $Conditions; logbook = @{ value = 'Audit.Exchange' } } })
        $Response.StatusCode | Should -Be 400
        $Response.Body.error | Should -BeLike $Error
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'refuses a repeated activity alert on an operation it should not count' {
        $Response = Invoke-AddAlert -Request ([pscustomobject]@{ Body = [pscustomobject]@{ conditions = @(New-Condition 'Operation' 'in' @('FileDeleted', 'FileAccessed')); logbook = @{ value = 'Audit.SharePoint' }; thresholdEnabled = $true; threshold = @{ Count = 50; Minutes = 20 } } })
        $Response.StatusCode | Should -Be 400
        $Response.Body.error | Should -BeLike "*can't count FileAccessed*"
        Should -Invoke Add-CIPPAzDataTableEntity -Times 0 -Exactly
    }

    It 'keeps the repeated activity operations the same for the backend and the alert form' {
        $Backend = Get-Content -Raw (Join-Path $RepoRoot 'Config/AuditLogRepeatedActivityOperations.json') | ConvertFrom-Json
        $Frontend = Get-Content -Raw (Join-Path (Split-Path -Parent $RepoRoot) 'frontend/src/data/AuditLogRepeatedActivityOperations.json') | ConvertFrom-Json
        ($Frontend | ConvertTo-Json -Depth 5) | Should -Be ($Backend | ConvertTo-Json -Depth 5)
    }

    It 'refuses a repeated activity alert with more than one group' {
        $Conditions = @(
            (New-Condition 'Operation' 'eq' 'FileDeleted')
            (New-Condition 'Operation' 'eq' 'FileRecycled') | Add-Member -NotePropertyName Group -NotePropertyValue 1 -PassThru
        )
        $Response = Invoke-AddAlert -Request ([pscustomobject]@{ Body = [pscustomobject]@{ conditions = $Conditions; logbook = @{ value = 'Audit.SharePoint' }; thresholdEnabled = $true; threshold = @{ Count = 50; Minutes = 20 } } })
        $Response.StatusCode | Should -Be 400
        $Response.Body.error | Should -BeLike '*more than one group*'
    }

    It 'stores no threshold when it is switched off' {
        $null = Invoke-AddAlert -Request ([pscustomobject]@{ Body = [pscustomobject]@{ conditions = @(New-Condition 'Operation' 'eq' 'FileDeleted'); tenantFilter = @(@{ value = 'AllTenants' }); logbook = @{ value = 'Audit.SharePoint' }; thresholdEnabled = $false; threshold = @{ Count = 100; Minutes = 20 } } })
        Should -Invoke Add-CIPPAzDataTableEntity -Times 1 -Exactly -ParameterFilter { $null -eq $Entity.Threshold }
    }
}
