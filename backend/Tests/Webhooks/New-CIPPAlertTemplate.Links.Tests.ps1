# The links an audit log alert carries: to the saved log and to the settings of the alert that matched.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $env:CIPPRootPath = $RepoRoot
    function Get-CIPPMicrosoftFirstPartyApp { param($AppId) }
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/New-CIPPAlertTemplate.ps1')
    . (Join-Path $RepoRoot 'Modules/CIPPCore/Public/ConvertTo-PSAHtml.ps1')
    $script:Record = [pscustomobject]@{ Operation = 'New-InboxRule'; UserId = 'user1@contoso.com'; CIPPClause = 'Operation is Equals to New-InboxRule'; CIPPLocationInfo = $null; CIPPParameters = '[]' }
    $script:LogLink = 'https://cipp.invalid/tenant/administration/audit-logs/log?id=rec-1&tenantFilter=contoso.com'
    $script:RuleLink = 'https://cipp.invalid/tenant/administration/alert-configuration/alert?id=rule-1'
}

Describe 'New-CIPPAlertTemplate links' {
    It 'links an email to the saved log and the alert''s settings' {
        $Html = (New-CIPPAlertTemplate -Format 'html' -Data $script:Record -CIPPURL 'https://cipp.invalid' -Tenant 'contoso.com' -AuditLogLink $script:LogLink -AlertConfigLink $script:RuleLink).htmlcontent
        $Html | Should -BeLike "*href=`"$($script:LogLink)`"*"
        $Html | Should -BeLike "*href=`"$($script:RuleLink)`"*"
    }

    It 'links a PSA ticket to each once' {
        $Html = (New-CIPPAlertTemplate -Format 'psa' -Data $script:Record -CIPPURL 'https://cipp.invalid' -Tenant 'contoso.com' -AuditLogLink $script:LogLink -AlertConfigLink $script:RuleLink).htmlcontent
        ([regex]::Matches($Html, [regex]::Escape($script:LogLink))).Count | Should -Be 1
        ([regex]::Matches($Html, [regex]::Escape($script:RuleLink))).Count | Should -Be 1
    }

    It 'leaves the settings link out when no alert rule is known' {
        $Html = (New-CIPPAlertTemplate -Format 'html' -Data $script:Record -CIPPURL 'https://cipp.invalid' -Tenant 'contoso.com' -AuditLogLink $script:LogLink).htmlcontent
        $Html | Should -Not -BeLike '*alert-configuration*'
    }
}
