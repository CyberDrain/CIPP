# Pins how an audit log rule's %variables% resolve per tenant before the prefilter and the engine read its conditions.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    function Get-CIPPTextReplacement { param($TenantFilter, $Text) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/Webhooks/Resolve-CIPPAuditLogConditionVariable.ps1')
    function New-Condition([string]$Property, [string]$Operator, $Value) {
        $InputValue = if ($Value -is [array]) { @(foreach ($Item in $Value) { [pscustomobject]@{ value = $Item; label = $Item } }) } else { [pscustomobject]@{ value = $Value; label = $Value } }
        [pscustomobject]@{ Property = [pscustomobject]@{ label = $Property; value = 'String' }; Operator = [pscustomobject]@{ label = $Operator; value = $Operator }; Input = $InputValue; Group = 1 }
    }
}

Describe 'Resolve-CIPPAuditLogConditionVariable' {
    BeforeEach {
        $script:Values = @{ '%breakglass%' = 'bg1@contoso.com, bg2@contoso.com'; '%defaultdomain%' = 'contoso.com' }
        Mock Get-CIPPTextReplacement { $Out = [string]$Text; foreach ($Key in $script:Values.Keys) { $Out = $Out.Replace($Key, $script:Values[$Key]) }; $Out }
    }

    It 'leaves conditions without a variable as they are, without looking anything up' {
        $Conditions = @((New-Condition 'Operation' 'eq' 'UserLoggedIn'), (New-Condition 'UserId' 'like' '*100%*'))
        $Out = @(Resolve-CIPPAuditLogConditionVariable -TenantFilter 'contoso.com' -Conditions $Conditions)
        $Out | Should -HaveCount 2
        $Out[1].Input.value | Should -Be '*100%*'
        Should -Invoke Get-CIPPTextReplacement -Times 0 -Exactly
    }

    It 'replaces a variable in a value and keeps the condition''s group' {
        $Out = @(Resolve-CIPPAuditLogConditionVariable -TenantFilter 'contoso.com' -Conditions @(New-Condition 'UserId' 'like' '*@%defaultdomain%'))
        $Out[0].Input.value | Should -Be '*@contoso.com'
        $Out[0].Group | Should -Be 1
    }

    It 'splits a variable into several values for In' {
        $Out = @(Resolve-CIPPAuditLogConditionVariable -TenantFilter 'contoso.com' -Conditions @(New-Condition 'UserId' 'in' @('%breakglass%', 'admin@contoso.com')))
        @($Out[0].Input.value) | Should -Be @('bg1@contoso.com', 'bg2@contoso.com', 'admin@contoso.com')
    }

    It 'gives nothing for a tenant without a value for the variable, so the rule is not checked there' {
        $script:Values = @{}
        @(Resolve-CIPPAuditLogConditionVariable -TenantFilter 'contoso.com' -Conditions @((New-Condition 'Operation' 'eq' 'UserLoggedIn'), (New-Condition 'UserId' 'in' @('%breakglass%'))) 3>$null) | Should -HaveCount 0
    }

    It 'gives nothing when a variable holds a character the engine will not run' {
        $script:Values = @{ '%breakglass%' = 'a$b@contoso.com' }
        @(Resolve-CIPPAuditLogConditionVariable -TenantFilter 'contoso.com' -Conditions @(New-Condition 'UserId' 'in' @('%breakglass%')) 3>$null) | Should -HaveCount 0
    }

    It 'gives nothing when a variable lists more than 500 values' {
        $script:Values = @{ '%breakglass%' = (@(1..501 | ForEach-Object { "u$_@contoso.com" }) -join ',') }
        @(Resolve-CIPPAuditLogConditionVariable -TenantFilter 'contoso.com' -Conditions @(New-Condition 'UserId' 'in' @('%breakglass%')) 3>$null) | Should -HaveCount 0
    }
}
