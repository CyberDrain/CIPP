# Pins what counts as an audit log rule's anchor, and that Invoke-AddAlert refuses a rule without one.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Get-CIPPAuditLogRuleAnchor.ps1')

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
}
