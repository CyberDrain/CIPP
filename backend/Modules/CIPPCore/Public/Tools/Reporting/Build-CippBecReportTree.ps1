function Build-CippBecReportTree {
    <#
    .SYNOPSIS
        Compose the BEC (Business Email Compromise) analysis report as a component tree - the server
        port of BECRemediationReportButton's BECRemediationReportDocument.
    .DESCRIPTION
        Returns the content blocks only; the cover (title/accent/tenant/label/subtitle/meta) is set by
        the caller through report variables, since the BEC cover names the compromised user rather than
        the tenant. Detail callouts use -Lines so each label/value line is a tight line break.
    .PARAMETER UserData
        The investigated user: displayName, userPrincipalName.
    .PARAMETER BecData
        The Push-BECRun payload (rules, sign-ins, apps, sent mail, location analysis, ...).
    .PARAMETER TenantName
        The tenant the user belongs to.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][hashtable]$UserData, [Parameter(Mandatory)][hashtable]$BecData, [string]$TenantName)

    $bec = $BecData
    $loc = $bec.LocationAnalysis
    $ana = $bec.SentMessageAnalysis

    function Cnt($x) { if ($null -eq $x) { return 0 }; @($x).Count }
    function FmtDate($d) {
        if (-not $d) { return 'N/A' }
        try { return ([datetime]$d).ToString('MMM d, yyyy, hh:mm tt', [Globalization.CultureInfo]::InvariantCulture) } catch { return "$d" }
    }
    function FmtSafelist($v) {
        if (-not $v) { return 'unchanged' }
        if ($v -is [array]) { $j = ($v -join ', '); if ($j) { return $j } else { return 'unchanged' } }
        return "$v"
    }

    # -- statistics (mirrors the client stats object) --
    $stats = @{
        newRules                        = Cnt $bec.NewRules
        ruleChanges                     = Cnt $bec.InboxRuleChanges
        newUsers                        = Cnt $bec.NewUsers
        newApps                         = Cnt $bec.AddedApps
        permissionChanges               = Cnt $bec.MailboxPermissionChanges
        permissionChangesTargetingUser  = Cnt @($bec.MailboxPermissionChanges | Where-Object { $_.TargetsSuspect -eq $true })
        mfaDevices                      = Cnt $bec.MFADevices
        passwordChanges                 = Cnt $bec.ChangedPasswords
        sentMessages                    = Cnt $bec.SentMessages
        trustedSenders                  = Cnt $bec.TrustedSenders
        blockedSenders                  = Cnt $bec.BlockedSenders
        safelistChanges                 = Cnt $bec.SafelistChanges
        sharingChanges                  = Cnt $bec.SharingChanges
        anonymousLinks                  = Cnt @($bec.SharingChanges | Where-Object { "$($_.Operation)".StartsWith('AnonymousLink') })
        intuneDevices                   = Cnt $bec.IntuneDevices
        signIns                         = Cnt $bec.SuspectUserSignIns
        sentTotalMessages               = [int]$(if ($null -ne $ana.TotalMessages) { $ana.TotalMessages } else { 0 })
        sentTotalRecipients             = [int]$(if ($null -ne $ana.TotalRecipients) { $ana.TotalRecipients } else { 0 })
        repeatedSubjects                = [int]$(if ($ana.FlaggedSubjectCount) { $ana.FlaggedSubjectCount } else { 0 })
        sendBursts                      = Cnt $ana.Bursts
        massMailFlagged                 = ($ana.Flagged -eq $true)
        maliciousApps                   = (Cnt @($bec.AddedApps | Where-Object { $_.MaliciousMatch })) + (Cnt $bec.MaliciousSPs)
        foreignSignIns                  = [int]$(if ($loc.ForeignSignInCount) { $loc.ForeignSignInCount } else { 0 })
        foreignSuccessfulSignIns        = [int]$(if ($loc.ForeignSuccessfulSignInCount) { $loc.ForeignSuccessfulSignInCount } else { 0 })
        foreignSentMessages             = [int]$(if ($loc.ForeignSentMessageCount) { $loc.ForeignSentMessageCount } else { 0 })
    }
    $stats.foreignActivity = [int]$(if ($loc.ForeignRuleChangeCount) { $loc.ForeignRuleChangeCount } else { 0 }) +
    [int]$(if ($loc.ForeignSafelistChangeCount) { $loc.ForeignSafelistChangeCount } else { 0 }) +
    [int]$(if ($loc.ForeignSharingChangeCount) { $loc.ForeignSharingChangeCount } else { 0 }) +
    [int]$(if ($loc.ForeignSentMessageCount) { $loc.ForeignSentMessageCount } else { 0 })

    # analysis window: 7 days before extraction
    $extractedAt = try { [datetime]$bec.ExtractedAt } catch { Get-Date }
    $windowStart = $extractedAt.AddDays(-7)
    $recentIntune = @($bec.IntuneDevices | Where-Object { try { ([datetime]$_.enrolledDateTime) -ge $windowStart } catch { $false } })
    $stats.recentIntuneDevices = Cnt $recentIntune
    $isRecentMfa = { param($m) try { ([datetime]$m.createdDateTime) -ge $windowStart } catch { $false } }
    $stats.recentMfaDevices = Cnt @($bec.MFADevices | Where-Object { & $isRecentMfa $_ })

    # successful foreign sign-ins first
    $foreignSignInList = @($bec.SuspectUserSignIns | Where-Object { $_.ForeignLocation -eq $true } |
        Sort-Object -Property @{ Expression = { $_.Status -eq 'Success' }; Descending = $true })
    $sortedIntune = @($bec.IntuneDevices | Sort-Object -Property @{ Expression = { try { [datetime]$_.enrolledDateTime } catch { [datetime]0 } }; Descending = $true })

    # -- threat level --
    $score = 0
    if ($stats.newRules -gt 0) { $score += 3 }
    if ($stats.ruleChanges -gt 0) { $score += 3 }
    if ($stats.permissionChangesTargetingUser -gt 0) { $score += 2 } elseif ($stats.permissionChanges -gt 0) { $score += 1 }
    if ($stats.newApps -gt 0) { $score += 1 }
    if ($stats.newUsers -gt 5) { $score += 1 }
    if ($stats.safelistChanges -gt 0) { $score += 2 }
    if (@($bec.NewRules | Where-Object { "$($_.MoveToFolder)" -like '*RSS*' }).Count -gt 0) { $score += 5 }
    if ($stats.maliciousApps -gt 0) { $score += 5 }
    if ($stats.foreignSuccessfulSignIns -gt 0) { $score += 3 }
    if ($stats.foreignActivity -gt 0) { $score += 3 }
    if ($stats.anonymousLinks -gt 0) { $score += 3 }
    if ($stats.massMailFlagged) { $score += 3 }
    if ($stats.recentMfaDevices -gt 0) { $score += 2 }
    if ($stats.recentIntuneDevices -gt 0) { $score += 2 }
    if ($score -ge 7) { $threatLevel = 'High'; $threatColour = '#742A2A' }
    elseif ($score -ge 4) { $threatLevel = 'Medium'; $threatColour = '#744210' }
    else { $threatLevel = 'Low'; $threatColour = '#22543D' }

    $upn = $UserData.userPrincipalName
    $usageLoc = $loc.UsageLocation
    $b = [System.Collections.Generic.List[object]]::new()

    # === PAGE 1: EXECUTIVE SUMMARY ===
    $b.Add((New-CippReportPage -Title 'Executive Summary' -Subtitle 'Overview of Business Email Compromise investigation findings'))
    $b.Add((New-CippReportParagraph -Html ('<p>This report documents the findings of a Business Email Compromise (BEC) investigation performed for the user account <b>{0}</b> within <b>{1}</b>. The investigation analyzed suspicious activity indicators including mailbox rules, permission changes, new applications, authentication patterns, and sign-in locations over a 7-day period.</p>' -f [System.Net.WebUtility]::HtmlEncode([string]$upn), [System.Net.WebUtility]::HtmlEncode([string]$TenantName))))
    $b.Add((New-CippReportParagraph -Text 'Business Email Compromise is a sophisticated scam targeting organizations that regularly perform wire transfers or have established relationships with foreign suppliers. Attackers compromise legitimate email accounts through social engineering or computer intrusion techniques to conduct unauthorized fund transfers, steal sensitive information, or impersonate executives.'))

    $b.Add((New-CippReportHeading -Title 'Investigation Overview'))
    $b.Add((New-CippReportStatRow -Stats @(
                @{ value = $stats.newRules; label = 'Mailbox Rules' }
                @{ value = $stats.permissionChanges; label = 'Permission Changes' }
                @{ value = $stats.foreignSignIns; label = 'Foreign Sign-ins' }
                @{ value = $stats.maliciousApps; label = 'Malicious Apps' }
            )))
    $threatText = switch ($threatLevel) {
        'High' { 'HIGH RISK: Multiple indicators of compromise detected. Immediate remediation actions are strongly recommended. This account shows patterns consistent with active Business Email Compromise attacks.' }
        'Medium' { 'MEDIUM RISK: Suspicious activity patterns detected. Review findings and consider implementing recommended security measures. Some indicators suggest potential unauthorized access.' }
        default { 'LOW RISK: Minimal suspicious activity detected. The findings show standard user behavior with no significant indicators of compromise. Continue monitoring as a precautionary measure.' }
    }
    $b.Add((New-CippReportAlertBox -Colour $threatColour -Title "Threat Assessment: $threatLevel" -Content $threatText))

    $b.Add((New-CippReportHeading -Title 'Data Source Information'))
    $b.Add((New-CippReportInfoBox -Title 'Audit Log Status' -Content $(if ($bec.ExtractResult) { "$($bec.ExtractResult)" } else { 'Unknown' })))
    $b.Add((New-CippReportInfoBox -Title 'Analysis Period' -Content ("Last 7 days ending {0}" -f (FmtDate $bec.ExtractedAt))))
    $b.Add((New-CippReportInfoBox -Title 'Assigned Usage Location' -Content $(if ($usageLoc) { "$usageLoc" } else { 'Not assigned - sign-ins and activity could not be compared against an expected country' })))

    # === PAGE 2: UNDERSTANDING BEC ===
    $b.Add((New-CippReportPage -Title 'Understanding Business Email Compromise' -Subtitle 'What is BEC and why does it matter?'))
    $b.Add((New-CippReportParagraph -Title 'What is Business Email Compromise?' -Text 'Business Email Compromise (BEC) is a type of cyberattack where criminals gain unauthorized access to a business email account. Once inside, attackers can:'))
    $b.Add((New-CippReportBullets -Items @(
                @{ label = 'Monitor communications:'; text = 'Read sensitive emails to learn about business operations, financial processes, and key relationships.' }
                @{ label = 'Impersonate executives:'; text = 'Send fraudulent emails appearing to come from company leadership requesting wire transfers or sensitive data.' }
                @{ label = 'Manipulate transactions:'; text = 'Intercept legitimate invoices and alter payment information to redirect funds to attacker-controlled accounts.' }
                @{ label = 'Hide their tracks:'; text = 'Create email rules to automatically delete or hide messages, preventing detection.' }
            )))
    $b.Add((New-CippReportParagraph -Title 'Common Attack Methods' -Text 'Attackers typically gain access to email accounts through:'))
    $b.Add((New-CippReportBullets -Items @(
                @{ label = 'Phishing:'; text = 'Deceptive emails that trick users into providing their login credentials on fake websites.' }
                @{ label = 'Password Spraying:'; text = 'Automated attempts to log in using common passwords across many accounts.' }
                @{ label = 'Credential Stuffing:'; text = 'Using usernames and passwords leaked from other breached websites.' }
                @{ label = 'Malware:'; text = 'Software that captures keystrokes or steals stored passwords from compromised devices.' }
            )))
    $b.Add((New-CippReportParagraph -Title 'Why This Investigation Was Performed' -Text 'This analysis was initiated because suspicious activity was detected or reported for this user account. The investigation examines multiple indicators that might suggest account compromise, including unusual mailbox rules, unexpected permission changes, new application authorizations, and abnormal sign-in patterns. Early detection is critical to minimize potential damage and prevent financial loss or data theft.'))

    # === PAGE 3: DETAILED FINDINGS - Check 1 ===
    $b.Add((New-CippReportPage -Title 'Detailed Findings' -Subtitle 'Investigation results and analysis'))
    $b.Add((New-CippReportHeading -Title 'Check 1: Mailbox Rules'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Attackers often create email rules to automatically forward, delete, or hide messages. This prevents victims from seeing evidence of fraudulent activity. Suspicious rules may move emails to obscure folders like "RSS Subscriptions" or forward them to external addresses.'))
    if ($stats.newRules -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($stats.newRules) Mailbox Rule(s) Found" -Content 'The following mailbox rules were detected. Review each rule carefully to determine if it was created by the user or by an attacker. Rules that forward emails or move them to unusual folders are particularly suspicious.'))
        foreach ($rule in @($bec.NewRules | Select-Object -First 10)) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("Description: $(if ($rule.Description) { $rule.Description } else { 'No description available' })")
            if ($rule.MoveToFolder) { $lines.Add("Moves to: $($rule.MoveToFolder)") }
            if ($rule.ForwardTo) { $lines.Add("Forwards to: $($rule.ForwardTo)") }
            if ($rule.DeleteMessage) { $lines.Add('Deletes messages') }
            if ($rule.RecentlyChanged) { $lines.Add('Created or changed in the last 7 days') }
            $b.Add((New-CippReportInfoBox -Lines -Title "Rule: $(if ($rule.Name) { $rule.Name } else { 'Unnamed Rule' })" -Content ($lines -join "`n")))
        }
        if ($stats.newRules -gt 10) { $b.Add((New-CippReportNote -Text "... and $($stats.newRules - 10) more rules (see JSON export for full list)")) }
    }
    if ($stats.ruleChanges -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($stats.ruleChanges) Rule Change(s) in the Last 7 Days" -Content 'The audit log recorded inbox rules being created, changed or removed on this mailbox. Rules that were removed after use are a common way for attackers to cover their tracks.'))
        foreach ($change in @($bec.InboxRuleChanges | Select-Object -First 10)) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("Date: $(if ($change.Date) { $change.Date } else { 'Unknown' })")
            $lines.Add("By: $(if ($change.UserKey) { $change.UserKey } else { 'Unknown' })")
            if ($change.ClientIP) { $lines.Add("From: $($change.ClientIP)$(if ($change.Country) { " ($($change.Country))" })") }
            if ($change.ForeignLocation -eq $true) { $lines.Add('[!] Originated outside the assigned usage location') }
            if ($change.Parameters) { $lines.Add("Parameters: $($change.Parameters)") }
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($change.Operation) { $change.Operation } else { 'Rule Change' }): $(if ($change.RuleName) { $change.RuleName } else { 'Unnamed Rule' })" -Content ($lines -join "`n")))
        }
        if ($stats.ruleChanges -gt 10) { $b.Add((New-CippReportNote -Text "... and $($stats.ruleChanges - 10) more changes (see JSON export for full list)")) }
    }
    if ($stats.newRules -eq 0 -and $stats.ruleChanges -eq 0) {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Suspicious Rules Found' -Content 'No mailbox rules were detected that match suspicious patterns. This is a positive indicator.'))
    }

    # === PAGE 4: DETAILED FINDINGS (Continued) - Check 2, 3 ===
    $b.Add((New-CippReportPage -Title 'Detailed Findings (Continued)' -Subtitle 'Investigation results and analysis'))
    $b.Add((New-CippReportHeading -Title 'Check 2: Recently Created Users'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Attackers sometimes create new user accounts to maintain persistent access or to use as staging accounts for fraudulent activities. Reviewing recently created users helps identify unauthorized account creation.'))
    if ($stats.newUsers -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[i] $($stats.newUsers) New User(s) Found" -Content 'The following users were created in the last 7 days. Verify that each account creation was authorized and legitimate.'))
        foreach ($u in @($bec.NewUsers | Select-Object -First 8)) {
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($u.displayName) { $u.displayName } else { 'Unknown' })" -Content ("Email: $(if ($u.userPrincipalName) { $u.userPrincipalName } else { 'N/A' })`nCreated: $(FmtDate $u.createdDateTime)")))
        }
        if ($stats.newUsers -gt 8) { $b.Add((New-CippReportNote -Text "... and $($stats.newUsers - 8) more users (see JSON export for full list)")) }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No New Users Found' -Content 'No new user accounts were created during the analysis period.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 3: New Applications'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content "Attackers may authorize malicious or suspicious third-party applications to access your email and data. These applications can read emails, send messages, and access files without the user's explicit knowledge."))
    if ($stats.maliciousApps -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($stats.maliciousApps) Known-Malicious Application(s) Detected" -Content 'One or more applications in this tenant match the CIPP known-malicious application catalog. Consent-based access survives a password reset, so these applications should be removed unless their presence is explained.'))
    }
    if ($stats.newApps -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($stats.newApps) New Application(s) Found" -Content 'New applications were granted access during the analysis period. Review each application to ensure it was authorized and is from a trusted publisher.'))
        foreach ($app in @($bec.AddedApps | Select-Object -First 6)) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("Publisher: $(if ($app.publisher) { $app.publisher } else { 'Unknown' })")
            $lines.Add("App ID: $(if ($app.appId) { $app.appId } else { 'N/A' })")
            $lines.Add("Created: $(FmtDate $app.createdDateTime)")
            if ($app.MaliciousMatch) {
                $cats = if ($app.MaliciousMatch.Categories) { " ($($app.MaliciousMatch.Categories -join ', '))" } else { '' }
                $lines.Add("[!] Matches known-malicious catalog entry `"$($app.MaliciousMatch.Name)`"$cats")
            }
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($app.displayName) { $app.displayName } elseif ($app.appDisplayName) { $app.appDisplayName } else { 'Unknown' })" -Content ($lines -join "`n")))
        }
        if ($stats.newApps -gt 6) { $b.Add((New-CippReportNote -Text "... and $($stats.newApps - 6) more apps (see JSON export for full list)")) }
    } elseif ((Cnt $bec.MaliciousSPs) -eq 0) {
        $b.Add((New-CippReportClearBox -Title '[Pass] No New Applications Found' -Content 'No new applications were authorized during the analysis period, and no known malicious applications are present in the tenant.'))
    }
    if ((Cnt $bec.MaliciousSPs) -gt 0) {
        foreach ($app in @($bec.MaliciousSPs | Select-Object -First 6)) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("Catalog entry: $(if ($app.CatalogName) { $app.CatalogName } else { 'Unknown' })")
            $lines.Add("App ID: $(if ($app.appId) { $app.appId } else { 'N/A' })")
            $lines.Add("Categories: $(if ($app.Categories) { $app.Categories -join ', ' } else { 'N/A' })")
            $lines.Add("Enabled: $(if ($null -ne $app.accountEnabled) { $app.accountEnabled } else { 'Unknown' })")
            $lines.Add("First seen: $(FmtDate $app.createdDateTime)")
            $b.Add((New-CippReportInfoBox -Lines -Title "[!] $(if ($app.displayName) { $app.displayName } else { 'Unknown' }) (present in tenant)" -Content ($lines -join "`n")))
        }
        if ((Cnt $bec.MaliciousSPs) -gt 6) { $b.Add((New-CippReportNote -Text "... and $((Cnt $bec.MaliciousSPs) - 6) more (see JSON export for full list)")) }
    }

    # === PAGE 5: ADDITIONAL SECURITY CHECKS - Check 4,5,6,7 ===
    $b.Add((New-CippReportPage -Title 'Additional Security Checks' -Subtitle 'Permissions, outbound mail, authentication, and access patterns'))
    $b.Add((New-CippReportHeading -Title 'Check 4: Mailbox Permission Changes'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Unauthorized changes to mailbox permissions can allow attackers to grant themselves or accomplices access to read, send, or manage emails. This is a common technique to maintain persistent access.'))
    if ($stats.permissionChanges -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($stats.permissionChanges) Permission Change(s) Found" -Content 'Mailbox permission changes were detected. Verify that each change was authorized and necessary for legitimate business purposes.'))
        foreach ($change in @($bec.MailboxPermissionChanges | Select-Object -First 5)) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("User: $(if ($change.UserKey) { $change.UserKey } else { 'Unknown' })")
            $lines.Add("Target: $(if ($change.ObjectId) { $change.ObjectId } else { 'N/A' })")
            $lines.Add("Permissions: $(if ($change.Permissions) { $change.Permissions } else { 'Unknown' })")
            if ($change.TargetsSuspect -eq $true) { $lines.Add('[!] Targets the investigated mailbox') }
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($change.Operation) { $change.Operation } else { 'Permission Change' })" -Content ($lines -join "`n")))
        }
        if ($stats.permissionChanges -gt 5) { $b.Add((New-CippReportNote -Text "... and $($stats.permissionChanges - 5) more changes")) }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Permission Changes Found' -Content 'No mailbox permission changes were detected during the analysis period.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 5: Sent Messages'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Attackers use a compromised mailbox to send fraudulent invoices, phishing, or internal impersonation mail. The message trace shows what actually left the mailbox during the analysis period, including the IP address it was sent from.'))
    if ($stats.sentMessages -gt 0) {
        $totMsg = if ($stats.sentTotalMessages) { $stats.sentTotalMessages } else { $stats.sentMessages }
        $totRcp = if ($stats.sentTotalRecipients) { $stats.sentTotalRecipients } else { $stats.sentMessages }
        $foreignTail = if ($stats.foreignSentMessages -gt 0) { ", including $($stats.foreignSentMessages) from an IP outside the user's assigned usage location." } else { '.' }
        $b.Add((New-CippReportParagraph -Indent -Text "[i] $totMsg message(s) to $totRcp recipient(s) were sent by this mailbox during the analysis period$foreignTail"))
        if ($stats.massMailFlagged) {
            $mm = ''
            if ($stats.repeatedSubjects -gt 0) { $mm += "$($stats.repeatedSubjects) subject(s) were sent as many separate messages or to many recipients. " }
            if ($stats.sendBursts -gt 0) { $mm += "$($stats.sendBursts) short burst(s) of high-volume sending were detected. " }
            $mm += 'Identical-subject mass mail and send bursts are how a compromised mailbox spreads phishing or fraudulent invoices. Review the campaigns below and warn the recipients if the content was malicious.'
            $b.Add((New-CippReportAlertBox -Title '[!] Mass-Mail Pattern Detected' -Content $mm))
        }
        foreach ($g in @($ana.RepeatedSubjects | Select-Object -First 5)) {
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($g.Flagged) { '[!] ' })Repeated subject: $(if ($g.Subject) { $g.Subject } else { '(no subject)' })" -Content ("Messages: $($g.MessageCount)`nRecipients: $($g.RecipientCount)`nFirst sent: $(if ($g.FirstSent) { $g.FirstSent } else { 'N/A' })`nLast sent: $(if ($g.LastSent) { $g.LastSent } else { 'N/A' })")))
        }
        if ((Cnt $ana.RepeatedSubjects) -gt 5) { $b.Add((New-CippReportNote -Text "... and $((Cnt $ana.RepeatedSubjects) - 5) more repeated subjects (see JSON export for full list)")) }
        foreach ($burst in @($ana.Bursts | Select-Object -First 5)) {
            $win = if ($burst.WindowMinutes) { $burst.WindowMinutes } else { 10 }
            $content = "Starting: $(if ($burst.WindowStart) { $burst.WindowStart } else { 'N/A' })"
            if ($burst.TopSubject) { $content += "`nMost common subject: $($burst.TopSubject)" }
            $b.Add((New-CippReportInfoBox -Lines -Title "[!] Send burst: $($burst.MessageCount) message(s) to $($burst.RecipientCount) recipient(s) in $win minutes" -Content $content))
        }
        if ((Cnt $ana.Bursts) -gt 5) { $b.Add((New-CippReportNote -Text "... and $((Cnt $ana.Bursts) - 5) more bursts (see JSON export for full list)")) }
        foreach ($msg in @($bec.SentMessages | Select-Object -First 10)) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("To: $(if ($msg.RecipientAddress) { $msg.RecipientAddress } else { 'N/A' })")
            $lines.Add("Status: $(if ($msg.Status) { $msg.Status } else { 'N/A' })")
            $lines.Add("Received: $(if ($msg.Received) { $msg.Received } else { 'N/A' })")
            if ($msg.FromIP) { $lines.Add("From IP: $($msg.FromIP)$(if ($msg.Country) { " ($($msg.Country))" })") }
            if ($msg.ForeignLocation -eq $true) { $lines.Add('[!] Sent from outside the assigned usage location') }
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($msg.Subject) { $msg.Subject } else { '(no subject)' })" -Content ($lines -join "`n")))
        }
        if ($stats.sentMessages -gt 10) { $b.Add((New-CippReportNote -Text "... and $($stats.sentMessages - 10) more messages (see JSON export for full list)")) }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Sent Messages Found' -Content 'No messages were sent by this mailbox during the analysis period.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 6: MFA Devices'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Multi-factor authentication (MFA) devices provide an additional layer of security. Reviewing registered MFA methods helps identify if attackers have added unauthorized devices to bypass security controls.'))
    if ($stats.mfaDevices -gt 0) {
        $mfaTail = if ($stats.recentMfaDevices -gt 0) { ", including $($stats.recentMfaDevices) registered in the last 7 days. Verify the recent registrations were made by the user - attackers register their own method to keep access after a password reset." } else { '. Verify each device belongs to the user.' }
        $b.Add((New-CippReportParagraph -Indent -Text "[i] $($stats.mfaDevices) MFA device(s) registered$mfaTail"))
        $sortedMfa = @($bec.MFADevices | Sort-Object -Property @{ Expression = { try { [datetime]$_.createdDateTime } catch { [datetime]0 } }; Descending = $true } | Select-Object -First 5)
        foreach ($device in $sortedMfa) {
            $type = "$($device.'@odata.type')".Replace('#microsoft.graph.', '').Replace('AuthenticationMethod', '')
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("Display Name: $(if ($device.displayName) { $device.displayName } else { 'N/A' })")
            $lines.Add("Registered: $(FmtDate $device.createdDateTime)")
            if (& $isRecentMfa $device) { $lines.Add('[!] Registered in the last 7 days') }
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($type) { $type } else { 'Unknown' })" -Content ($lines -join "`n")))
        }
        if ($stats.mfaDevices -gt 5) { $b.Add((New-CippReportNote -Text "... and $($stats.mfaDevices - 5) more methods (see JSON export for full list)")) }
    } else {
        $b.Add((New-CippReportInfoBox -Tone warn -Title '[!] No MFA Devices Found' -Content 'No multi-factor authentication devices are registered. MFA is highly recommended to prevent unauthorized access.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 7: Recent Password Changes'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content "Attackers often change passwords to lock out legitimate users. Reviewing recent password changes in the tenant helps identify if the compromised account's password was changed or if other accounts were affected."))
    if ($stats.passwordChanges -gt 0) {
        $b.Add((New-CippReportParagraph -Indent -Text "[i] $($stats.passwordChanges) password change(s) detected in the tenant during the analysis period."))
        foreach ($u in @($bec.ChangedPasswords | Select-Object -First 5)) {
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($u.displayName) { $u.displayName } else { 'Unknown' })" -Content ("Email: $(if ($u.userPrincipalName) { $u.userPrincipalName } else { 'N/A' })`nLast Password Change: $(FmtDate $u.lastPasswordChangeDateTime)")))
        }
        if ($stats.passwordChanges -gt 5) { $b.Add((New-CippReportNote -Text "... and $($stats.passwordChanges - 5) more (see JSON export for full list)")) }
    } else {
        $b.Add((New-CippReportParagraph -Indent -Text '[i] No password changes detected during the analysis period.'))
    }

    # === PAGE 6: MAILBOX LISTS, DEVICES & LOCATIONS - Check 8,9,10,11 ===
    $b.Add((New-CippReportPage -Title 'Mailbox Lists, Devices & Locations' -Subtitle 'Sender lists, managed devices, and sign-in origins'))
    $b.Add((New-CippReportHeading -Title 'Check 8: Trusted & Blocked Senders'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Attackers may add their own domain to the Trusted Senders list so their fraudulent messages bypass spam filtering, or add finance/security domains to the Blocked Senders list so warnings and alerts are hidden from the victim in the Junk Email folder.'))
    if ($bec.SafelistError) {
        $b.Add((New-CippReportAlertBox -Lines -Title '[!] Could Not Retrieve Sender Lists' -Content ("$($bec.SafelistError)`nAn empty list here does not mean the mailbox has no trusted or blocked senders.")))
    }
    if ($stats.safelistChanges -gt 0) {
        $b.Add((New-CippReportAlertBox -Title "[!] $($stats.safelistChanges) Safelist Change(s) in the Last 7 Days" -Content 'The audit log recorded changes to the Trusted/Blocked Senders and Domains list on this mailbox. Review each change carefully.'))
        foreach ($change in @($bec.SafelistChanges | Select-Object -First 10)) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("Date: $(FmtDate $change.Date)")
            if ($change.ClientIP) { $lines.Add("From: $($change.ClientIP)$(if ($change.Country) { " ($($change.Country))" })") }
            if ($change.ForeignLocation -eq $true) { $lines.Add('[!] Originated outside the assigned usage location') }
            $lines.Add("Trusted: $(FmtSafelist $change.Trusted)")
            $lines.Add("Blocked: $(FmtSafelist $change.Blocked)")
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($change.Operation) { $change.Operation } else { 'Safelist Change' }) by $(if ($change.UserKey) { $change.UserKey } else { 'Unknown' })" -Content ($lines -join "`n")))
        }
        if ($stats.safelistChanges -gt 10) { $b.Add((New-CippReportNote -Text "... and $($stats.safelistChanges - 10) more changes (see JSON export for full list)")) }
    }
    if ($stats.trustedSenders -gt 0) {
        $b.Add((New-CippReportInfoBox -Title "Trusted Senders/Domains ($($stats.trustedSenders))" -Content (@($bec.TrustedSenders | Select-Object -First 15) -join ', ')))
    }
    if ($stats.trustedSenders -gt 15) { $b.Add((New-CippReportNote -Text "... and $($stats.trustedSenders - 15) more trusted entries (see JSON export for full list)")) }
    if ($stats.blockedSenders -gt 0) {
        $b.Add((New-CippReportInfoBox -Title "Blocked Senders/Domains ($($stats.blockedSenders))" -Content (@($bec.BlockedSenders | Select-Object -First 15) -join ', ')))
    }
    if ($stats.blockedSenders -gt 15) { $b.Add((New-CippReportNote -Text "... and $($stats.blockedSenders - 15) more blocked entries (see JSON export for full list)")) }
    if (-not $bec.SafelistError -and $stats.trustedSenders -eq 0 -and $stats.blockedSenders -eq 0 -and $stats.safelistChanges -eq 0) {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Trusted or Blocked Senders Found' -Content 'No trusted or blocked sender/domain entries were found on this mailbox.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 9: Intune Devices'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Newly enrolled Intune devices can indicate an attacker standing up a VM or BYOD endpoint under the compromised identity, including paths that re-register Windows Hello for Business. Review devices enrolled during the analysis window first.'))
    if ($bec.IntuneDevicesError) {
        $b.Add((New-CippReportAlertBox -Lines -Title '[!] Could Not Retrieve Intune Devices' -Content ("$($bec.IntuneDevicesError)`nAn empty device list here does not mean the user has no Intune devices.")))
    } elseif ($stats.intuneDevices -gt 0) {
        $intuneTail = if ($stats.recentIntuneDevices -gt 0) { ", including $($stats.recentIntuneDevices) enrolled in the last 7 days." } else { '. None were enrolled in the last 7 days.' }
        $b.Add((New-CippReportParagraph -Indent -Text "[i] $($stats.intuneDevices) Intune-managed device(s) associated with this user$intuneTail"))
        foreach ($device in @($sortedIntune | Select-Object -First 5)) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("OS: $(if ($device.operatingSystem) { $device.operatingSystem } else { 'N/A' })$(if ($device.osVersion) { " $($device.osVersion)" })")
            $lines.Add("Enrolled: $(FmtDate $device.enrolledDateTime)")
            $lines.Add("Compliance: $(if ($device.complianceState) { $device.complianceState } else { 'N/A' })")
            $lines.Add("Enrollment Type: $(if ($device.deviceEnrollmentType) { $device.deviceEnrollmentType } else { 'N/A' })")
            if ($device.serialNumber) { $lines.Add("Serial: $($device.serialNumber)") }
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($device.deviceName) { $device.deviceName } else { 'Unknown device' })" -Content ($lines -join "`n")))
        }
        if ((Cnt $sortedIntune) -gt 5) { $b.Add((New-CippReportNote -Text "... and $((Cnt $sortedIntune) - 5) more devices (see JSON export for full list)")) }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Intune Devices Found' -Content 'No Intune-managed devices were found for this user.'))
    }

    $b.Add((New-CippReportHeading -Title 'Check 10: Sign-in Locations'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content ("Sign-ins from countries the user does not work from are one of the strongest compromise indicators. Each sign-in is compared against the user's assigned usage location in Entra ID$(if ($usageLoc) { " ($usageLoc)" }), and the client IPs behind rule changes, safelist changes, sharing changes, and sent mail are geo-located and compared the same way.")))
    if ($bec.SuspectUserSignInsError) {
        $b.Add((New-CippReportAlertBox -Lines -Title '[!] Could Not Retrieve Sign-in Logs' -Content ("$($bec.SuspectUserSignInsError)`nAn empty list here does not mean the user has not signed in.")))
    } else {
        if (-not $usageLoc) {
            $b.Add((New-CippReportInfoBox -Tone warn -Title '[!] No Usage Location Assigned' -Content $(if ($loc.Note) { "$($loc.Note)" } else { 'The user has no usage location assigned in Entra ID, so activity cannot be compared against an expected country.' })))
        }
        if ((Cnt $loc.SignInCountries) -gt 0) {
            $b.Add((New-CippReportInfoBox -Lines -Title "Sign-in Countries Observed (last $($stats.signIns) sign-ins)" -Content ((@($loc.SignInCountries | ForEach-Object { "$($_.Country): $($_.Count) sign-in(s)" })) -join "`n")))
        }
        if ($stats.foreignSignIns -gt 0 -or $stats.foreignActivity -gt 0) {
            $b.Add((New-CippReportAlertBox -Title '[!] Activity Outside the Assigned Usage Location' -Content ("$($stats.foreignSignIns) sign-in(s) (of which $($stats.foreignSuccessfulSignIns) succeeded), $([int]$(if ($loc.ForeignRuleChangeCount) { $loc.ForeignRuleChangeCount } else { 0 })) inbox rule change(s), $([int]$(if ($loc.ForeignSafelistChangeCount) { $loc.ForeignSafelistChangeCount } else { 0 })) safelist change(s), $([int]$(if ($loc.ForeignSharingChangeCount) { $loc.ForeignSharingChangeCount } else { 0 })) sharing change(s), and $([int]$(if ($loc.ForeignSentMessageCount) { $loc.ForeignSentMessageCount } else { 0 })) sent message(s) originated outside $usageLoc. Failed foreign sign-ins are mostly password-spray noise; the successful ones prove access. Review each carefully - a single legitimate trip can explain some of this, but rule, safelist, or sharing changes from a foreign IP rarely have an innocent explanation.")))
            foreach ($signIn in @($foreignSignInList | Select-Object -First 10)) {
                $b.Add((New-CippReportInfoBox -Lines -Title "$(FmtDate $signIn.CreatedDateTime) - $(if ($signIn.Country) { $signIn.Country } else { 'Unknown' })" -Content ("Application: $(if ($signIn.AppDisplayName) { $signIn.AppDisplayName } else { 'N/A' })`nIP Address: $(if ($signIn.IPAddress) { $signIn.IPAddress } else { 'N/A' })`nCity: $(if ($signIn.City) { $signIn.City } else { 'N/A' })`nResult: $(if ($signIn.Status) { $signIn.Status } else { 'N/A' })")))
            }
            if ((Cnt $foreignSignInList) -gt 10) { $b.Add((New-CippReportNote -Text "... and $((Cnt $foreignSignInList) - 10) more foreign sign-ins (see JSON export for full list)")) }
        } elseif ($usageLoc) {
            $b.Add((New-CippReportClearBox -Title '[Pass] No Foreign Activity Detected' -Content "All located sign-ins and activity match the user's assigned usage location ($usageLoc)."))
        }
    }

    $b.Add((New-CippReportHeading -Title 'Check 11: Sharing Links'))
    $b.Add((New-CippReportInfoBox -Title 'Why We Check This' -Content 'Attackers share OneDrive and SharePoint folders to give themselves a data feed that survives a password reset, and anonymous links expose the content to anyone holding the URL. This check lists every sharing link the account created or changed during the analysis period, including the IP address it was done from.'))
    if ($stats.sharingChanges -gt 0) {
        $anon = if ($stats.anonymousLinks -gt 0) { "$($stats.anonymousLinks) of these involve anonymous links, which anyone with the URL can open. " } else { '' }
        $b.Add((New-CippReportAlertBox -Title "[!] $($stats.sharingChanges) Sharing Change(s) in the Last 7 Days" -Content ("${anon}Review each link and remove any that are not explained, even if the account has since been remediated.")))
        foreach ($change in @($bec.SharingChanges | Select-Object -First 10)) {
            $lines = [System.Collections.Generic.List[string]]::new()
            $lines.Add("Date: $(FmtDate $change.Date)")
            $lines.Add("Workload: $(if ($change.Workload) { $change.Workload } else { 'N/A' })")
            if ($change.Target) { $lines.Add("Shared with: $($change.Target)") }
            if ($change.ClientIP) { $lines.Add("From: $($change.ClientIP)$(if ($change.Country) { " ($($change.Country))" })") }
            if ($change.ForeignLocation -eq $true) { $lines.Add('[!] Originated outside the assigned usage location') }
            $b.Add((New-CippReportInfoBox -Lines -Title "$(if ($change.Operation) { $change.Operation } else { 'Sharing Change' }): $(if ($change.FileName) { $change.FileName } elseif ($change.ItemUrl) { $change.ItemUrl } else { 'Unknown item' })" -Content ($lines -join "`n")))
        }
        if ($stats.sharingChanges -gt 10) { $b.Add((New-CippReportNote -Text "... and $($stats.sharingChanges - 10) more changes (see JSON export for full list)")) }
    } else {
        $b.Add((New-CippReportClearBox -Title '[Pass] No Sharing Changes Found' -Content 'No sharing links were created or changed by this account during the analysis period.'))
    }

    # === PAGE 7: RECOMMENDATIONS ===
    $b.Add((New-CippReportPage -Title 'Recommendations' -Subtitle 'Actions to take and prevention best practices'))
    $b.Add((New-CippReportParagraph -Title 'Immediate Actions Required' -Text 'Based on the investigation findings, the following actions should be taken immediately:'))
    $b.Add((New-CippReportBullets -Items @(
                @{ marker = '1.'; label = 'Reset Password:'; text = "Change the user's password immediately to prevent further unauthorized access." }
                @{ marker = '2.'; label = 'Revoke Sessions:'; text = 'Sign out the user from all active sessions to terminate any attacker access.' }
                @{ marker = '3.'; label = 'Remove Suspicious Rules:'; text = 'Delete any mailbox rules that forward, redirect, or hide emails, especially those moving messages to unusual folders.' }
                @{ marker = '4.'; label = 'Review MFA Devices:'; text = "Remove any MFA devices that the user doesn't recognize and re-register legitimate devices." }
                @{ marker = '5.'; label = 'Audit Permissions:'; text = 'Review and revoke any unauthorized mailbox permissions or application consents.' }
                @{ marker = '6.'; label = 'Monitor Account:'; text = 'Continue monitoring the account for suspicious activity for at least 30 days.' }
            )))
    $b.Add((New-CippReportParagraph -Title 'Long-Term Prevention Strategies' -Text 'To prevent future Business Email Compromise attacks, implement these security best practices:'))
    $b.Add((New-CippReportBullets -Items @(
                @{ label = 'Enforce Multi-Factor Authentication (MFA):'; text = 'Require MFA for all users, especially those with administrative privileges or access to financial systems.' }
                @{ label = 'Implement Security Awareness Training:'; text = 'Educate employees about phishing, social engineering, and how to identify suspicious emails. Regular training significantly reduces successful attacks.' }
                @{ label = 'Enable Advanced Threat Protection:'; text = 'Use email security solutions that detect and block phishing, malware, and suspicious attachments.' }
                @{ label = 'Configure Conditional Access Policies:'; text = 'Restrict access based on location, device compliance, and risk level to prevent unauthorized sign-ins.' }
                @{ label = 'Monitor Audit Logs:'; text = 'Regularly review audit logs for suspicious activities such as unusual sign-in patterns, rule creation, or permission changes.' }
                @{ label = 'Establish Financial Controls:'; text = 'Implement multi-person approval processes for wire transfers and payment changes to prevent fraudulent transactions.' }
            )))
    $b.Add((New-CippReportParagraph -Title 'User Education Points' -Text 'Share these key points with the affected user to help prevent future compromises:'))
    $b.Add((New-CippReportBullets -Items @(
                @{ text = 'Never click on links or open attachments in unexpected emails, even if they appear to come from known contacts.' }
                @{ text = 'Always verify unusual requests for money transfers or sensitive information through a separate communication channel (phone call, in person).' }
                @{ text = 'Use strong, unique passwords for each account and consider using a password manager.' }
                @{ text = 'Be cautious when authorizing new applications or granting permissions to third-party services.' }
                @{ text = 'Report suspicious emails or activities to your IT security team immediately.' }
            )))

    # === PAGE 8: COMPLIANCE & DOCUMENTATION ===
    $b.Add((New-CippReportPage -Title 'Compliance & Documentation' -Subtitle 'Meeting regulatory and audit requirements'))
    $b.Add((New-CippReportParagraph -Title 'Compliance Considerations' -Text 'This report supports compliance and documentation requirements for various security frameworks and regulatory standards:'))
    $b.Add((New-CippReportBullets -Items @(
                @{ label = 'ISO 27001:'; text = 'Demonstrates incident detection, analysis, and response procedures (Controls A.16.1.1 - A.16.1.7).' }
                @{ label = 'CMMC Level 2:'; text = 'Provides evidence of security incident monitoring, analysis, and documentation (AC.L2-3.1.12, AU.L2-3.3.1).' }
                @{ label = 'SOC 2 Type II:'; text = 'Documents detective and responsive controls for security incidents (CC7.3, CC7.4).' }
                @{ label = 'NIST CSF:'; text = 'Aligns with Detect (DE.AE, DE.CM) and Respond (RS.AN, RS.MI) functions.' }
                @{ label = 'GDPR:'; text = 'Demonstrates security breach detection and potential data breach assessment (Articles 32, 33).' }
            )))
    $b.Add((New-CippReportParagraph -Title 'Audit Trail' -Text 'This investigation and resulting documentation provide an audit trail for security incident response:'))
    $b.Add((New-CippReportInfoBox -Lines -Title 'Investigation Details' -Content (@(
                    "Investigation Date: $(FmtDate $bec.ExtractedAt)"
                    "Analyzed User: $upn"
                    "Organization: $TenantName"
                    'Analysis Period: 7 days'
                    "Assigned Usage Location: $(if ($usageLoc) { $usageLoc } else { 'Not assigned' })"
                    "Audit Log Status: $(if ($bec.ExtractResult) { $bec.ExtractResult } else { 'Unknown' })"
                ) -join "`n")))
    $b.Add((New-CippReportInfoBox -Lines -Title 'Findings Summary' -Content (@(
                    "Threat Level: $threatLevel"
                    "Mailbox Rules Found: $($stats.newRules)"
                    "Rule Changes: $($stats.ruleChanges)"
                    "Permission Changes: $($stats.permissionChanges) ($($stats.permissionChangesTargetingUser) targeting this mailbox)"
                    "New Applications: $($stats.newApps)"
                    "Known-Malicious Applications: $($stats.maliciousApps)"
                    "New Users: $($stats.newUsers)"
                    "Sent Messages: $(if ($stats.sentTotalMessages) { $stats.sentTotalMessages } else { $stats.sentMessages })"
                    "Repeated Subject Campaigns: $($stats.repeatedSubjects)"
                    "Send Bursts: $($stats.sendBursts)"
                    "MFA Devices: $($stats.mfaDevices)"
                    "Recent MFA Registrations (7d): $($stats.recentMfaDevices)"
                    "Password Changes: $($stats.passwordChanges)"
                    "Trusted Senders: $($stats.trustedSenders)"
                    "Blocked Senders: $($stats.blockedSenders)"
                    "Safelist Changes: $($stats.safelistChanges)"
                    "Sharing Changes: $($stats.sharingChanges)"
                    "Anonymous Links: $($stats.anonymousLinks)"
                    "Intune Devices: $($stats.intuneDevices)"
                    "Recent Intune Enrollments (7d): $($stats.recentIntuneDevices)"
                    "Foreign Sign-ins: $($stats.foreignSignIns) ($($stats.foreignSuccessfulSignIns) successful)"
                    "Foreign Rule/Safelist/Sharing/Mail Activity: $($stats.foreignActivity)"
                ) -join "`n")))
    $b.Add((New-CippReportParagraph -Title 'Document Retention' -Text "This report should be retained according to your organization's document retention policy and regulatory requirements. Typical retention periods range from 3-7 years depending on applicable compliance frameworks. Store this document securely with restricted access as it contains sensitive security information."))
    $b.Add((New-CippReportParagraph -Title 'Additional Resources' -Text 'For more information about Business Email Compromise and cybersecurity best practices:'))
    $b.Add((New-CippReportBullets -Items @(
                @{ text = 'FBI IC3: Internet Crime Complaint Center (ic3.gov)' }
                @{ text = 'CISA: Cybersecurity & Infrastructure Security Agency (cisa.gov)' }
                @{ text = 'Microsoft Security: Business Email Compromise resources' }
            )))

    , @($b)
}
