function Get-CIPPBecRunSteps {
    <#
    .SYNOPSIS
        The ordered progress steps of a BEC investigation.
    .DESCRIPTION
        Push-BECRun reports its progress through the async-deployment rows (the same mechanism the
        SharePoint template deployment uses), one step per phase. This is the single definition of
        those phases so the run, the endpoint that queues it and the page that renders the steps
        agree on the list. Every run is the full investigation; the last step is always the
        location analysis, score and report.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Steps = [System.Collections.Generic.List[object]]::new()
    $Add = { param($Key, $Title) $Steps.Add([pscustomobject]@{ Key = $Key; Title = $Title }) }

    & $Add 'AuditLog' 'Unified audit log: rules, permissions, safelists and sharing'
    & $Add 'SignIns' 'Sign-ins and mobile devices'
    & $Add 'MailboxRules' 'Inbox rules, safelists and sharing links'
    & $Add 'SentMail' 'Sent message trace'
    & $Add 'Tenant' 'Tenant sign-ins, users, MFA methods and applications'
    & $Add 'MailboxInventory' 'Mailbox state, delegations and add-ins'
    & $Add 'Grants' 'Application consents'
    & $Add 'TransportRules' 'Transport rules'
    & $Add 'ReceivedMail' 'Received mail and Defender verdicts'
    & $Add 'Directory' 'Directory audits, registered devices and non-interactive sign-ins'
    & $Add 'Activity' 'Mailbox activity and Identity Protection'
    & $Add 'Score' 'Location analysis, threat score and report'

    return $Steps.ToArray()
}
