---
description: Single pane of glass review of common Indicators of Compromise (IoC)
---

# Compromise Remediation

This page gathers the signals worth checking when a mailbox is suspected of being compromised, so an investigation does not mean opening the Entra, Exchange, and Purview portals in turn. Each run of the analysis is kept as a case. A completed case opens with a triage header (the threat score, the signals behind it and the recommended containment), followed by the findings grouped by what an attacker would be trying to achieve, then the containment already taken and an attack timeline.

{% hint style="warning" %}
Nothing on this page is proof of a compromise. The checks surface the information that usually matters during an investigation, and several of them return results on perfectly healthy accounts. Read the findings alongside what you already know about the user and the tenant.
{% endhint %}

## Running the Analysis

Nothing runs when the page opens. It loads the user's runs and shows the latest one, or a **Business Email Compromise** status card with **Run investigation** when the user has none. Starting a run queues a background job, and the status card shows whether it is **Queued - waiting for a worker** or **Running**, with the step it is on and each step's outcome as it completes. A run usually takes a few minutes; a tenant with a lot of audit data can take up to ten. A run that makes no progress for twenty minutes, typically because the background worker restarted, is marked **Failed** with the reason shown, and the button becomes **Run a new investigation**. The failed run stays in the user's history.

A step that fails, or stops before it finishes, does not end the run: the remaining steps still run, and the checks from the failed step show as failed on the completed case, listed in the warning above the findings. Only a failure in the last step, which scores the run and builds the case, marks the whole run **Failed**.

While a run is queued or in progress, the status card also offers **Contain user**, so containment does not have to wait for the investigation to finish. Because there are no findings yet, the drawer's targets come from the live tenant rather than the case. The result is still recorded on the case, and a **Remediation taken** card appears below the status card once containment has run.

Every run is kept as a **case** with its own id (`BEC-<timestamp>-<suffix>`), so returning to the page shows the user's latest case rather than starting a new one. **← All BEC cases** goes back to the [Business Email Compromise](README.md) page, which lists every case for every user and tenant and is where runs are deleted.

Runs can also be queued for many users at once. Select the users on the [Users](../users/README.md) page and choose **BEC Remediation**, or use **Start investigation** on the [Business Email Compromise](README.md) page. One run per user is queued, and the Queue page tracks them together under one entry. Each run is a separate case and shows up on the [Business Email Compromise](README.md) page and in the user's own case list as it completes.

Everything collected is metadata: audit records, sign-ins, directory audits, message-trace headers, permissions, consents, rules and devices. No message body, attachment or file content is ever read or stored, which keeps the investigation inside what a partner relationship permits.

## Triage Header

The header of a completed case answers three questions before any evidence: how serious it looks, why, and what to do.

| Part                    | What it shows                                                                                                                                                                                                                                                                                                                                 |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Title                   | The user's name and the case id. When the user has more than one case, the title becomes a **Case** switcher instead, with each entry showing the run's date, threat level and case id. Pick one to view it exactly as it was collected. A chip beside it shows the threat level and score.                                                     |
| threat score            | The case's score and level, with the thresholds (High ≥ 7 · Medium ≥ 4). How the score is built is under [Threat Score](case.md#threat-score "mention").                                                                                                                                                                                         |
| Why                     | Every scoring signal that fired, highest weight first, with the points it added and how many results it counted. Select a signal to open the findings group that produced it and scroll to it. When checks could not run for want of a licence, permission, mailbox or service, a line below says how many and that the score may be understated. |
| Recommended containment | The containment actions the drawer starts with, which are the ones switched on in [BEC Remediation Defaults](../../../cipp/settings/bec-remediation.md), plus one line for each kind of finding that gives the drawer targets waiting: suspicious inbox rules, flagged delegations, risky consents, risky transport-rule changes, flagged add-ins and new registered devices. |

### Actions

| Action                 | Description                                                                                                                                                                                                                                                                                                                         |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Run new investigation  | Starts a new run of all 21 checks. The earlier case stays in the list. Use it when the data on screen predates something you need to see, such as a rule created in the last few minutes or a device you have just retired. The page shows the run's progress while it completes.                                                    |
| Review IPs             | Opens the **Review IP addresses** drawer, where you can confirm or correct the verdict on each address and re-run the parts of the case that depend on them. See [#reviewing-ip-verdicts](case.md#reviewing-ip-verdicts "mention").                                                                                                  |
| Contain user           | Opens the containment drawer described under [#containment](case.md#containment "mention"): pick the actions and their targets, type the UPN for critical ones, run.                                                                                                                                                                |
| Generate PDF Report    | Opens a preview of the report for the case, with a toggle between **C-suite summary** and **Full report**. **Download PDF** saves whichever is showing. What the report contains is covered under [#pdf-report](case.md#pdf-report "mention").                                                                                          |
| Export evidence (ZIP)  | Builds the evidence package for the case on screen and downloads it. If an export fails, the button turns red and hovering it gives the reason. See [#evidence-export](case.md#evidence-export "mention").                                                                                                                            |

### Threat Score

The score is a total of fixed points, one contribution per signal, regardless of how many results that signal counted. It is calculated when the run completes and stored with the case, so the header, the PDF report and the evidence package all show the same number and the same list of signals.

| Signal                                                                                    | Points |
| ----------------------------------------------------------------------------------------- | ------ |
| Identity Protection lists the user as confirmed compromised                               | 5      |
| A consent to an application in the rogue-app catalogues                                   | 5      |
| An application in the tenant matching the known-malicious catalogue                       | 5      |
| A successful sign-in, activity or accepted password from an attacker address              | 4      |
| Identity Protection lists the user at high risk                                           | 4      |
| A transport rule with a diversion or suppression action changed in the window             | 4      |
| A suspicious inbox rule (see Inbox rules below)                                           | 4      |
| Mail opened, synced, deleted, moved or sent from an attacker address                      | 3      |
| A Microsoft Form created, edited or shared from an attacker address                       | 3      |
| Another mailbox reached through this account's delegated access from an attacker address  | 3      |
| Another account in the tenant signed in or acted from an attacker address                 | 3      |
| One or more inbox rule changes in the window                                              | 3      |
| A successful sign-in from outside the usage location                                      | 3      |
| A successful non-interactive sign-in from outside the usage location                      | 3      |
| A rule, safelist, sharing, or sent-mail action from outside the usage location            | 3      |
| An anonymous sharing link created or changed in the window                                | 3      |
| A mass-mail pattern (repeated subjects or send bursts)                                    | 3      |
| A consent with a high-risk scope from an unverified publisher, for an app new in the window | 3      |
| Mail received from a look-alike of one of the tenant's domains                            | 3      |
| A Defender-classified threat delivered to the mailbox                                     | 3      |
| OneDrive or SharePoint files touched from an attacker address                             | 2      |
| A permission change targeting the investigated mailbox                                    | 2      |
| One or more changes to the trusted or blocked senders list                                | 2      |
| An MFA method registered in the window                                                    | 2      |
| An Intune device enrolled in the window                                                   | 2      |
| An Entra device registered in the window                                                  | 2      |
| A flagged mailbox delegation (external, guest, catch-all on the Inbox or writing the Calendar) | 2      |
| A flagged directory-audit event                                                           | 2      |
| Hard deletes above the threshold, or mailbox access from outside the usage location       | 2      |
| Identity Protection lists the user at medium risk                                         | 2      |
| Permission changes elsewhere in the tenant only, except on Exchange's system mailboxes    | 1      |
| One or more inbox rules on the mailbox                                                    | 1      |
| One or more new applications                                                              | 1      |
| More than five new users                                                                  | 1      |
| A side-loaded, non-Marketplace, non-Microsoft add-in                                      | 1      |
| Identity Protection lists the user at low risk                                            | 1      |

Seven points or more reads as **High**, four to six as **Medium**, and anything below that as **Low**.

{% hint style="warning" %}
Scoring counts findings, not volume, and a finding scores for what makes it suspicious, not for existing. Ordinary inbox rules score one point however many there are; a suspicious rule adds four, which is Medium on its own and High once anything else corroborates it, such as the rule being created in the window. Activity from an address judged a Microsoft service, a trusted address or the user's own is never counted as foreign, wherever it geolocates.
{% endhint %}

{% hint style="warning" %}
New users, new applications, and permission changes are tenant-wide checks, but each carries a single point unless a permission change targets the investigated mailbox. Tenant churn nudges the score rather than driving it. A wrongly-set usage location, on the other hand, can add three points through a perfectly normal successful sign-in, so check the assigned location before trusting a foreign-sign-in score.
{% endhint %}

{% hint style="danger" %}
Password changes carry no weight, and the MFA, Intune and registered-device lists only score for registrations and enrolments inside the window; long-standing methods and devices do not move the score however unfamiliar they look. Sent messages score only for a foreign-IP send or a mass-mail pattern. Failed sign-ins from foreign countries score nothing either: password spray hits every internet-facing tenant, so only a successful foreign sign-in counts, though the failures still show under **Interactive sign-ins**. A Low is a summary of what scored, not an all-clear; read the findings.
{% endhint %}

## Findings

Below the header, every finding sits in one of six collapsible groups, each named for what an attacker would be trying to achieve. A group's chip shows how many items it flagged, how many of its checks could not run (**not checked**), or **clear**. Groups with flagged findings open when the case loads; the rest start closed.

Inside a group, each finding carries its own chip:

| Chip            | Meaning                                                                                                                                                         |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| _n_ flagged     | Something worth attention. A line below the title says why, for example "inbox rule(s) that hide, forward, delete, or act on all incoming mail".              |
| not checked     | The check could not run, usually for want of a licence, permission, mailbox or service, and the finding says which. This is not a pass; the result is unknown. |
| partial         | The check could not read its whole window, and says where it stopped.                                                                                          |
| _n_ recorded    | Items found that are not flagged in themselves.                                                                                                                 |
| clear           | The check ran and found nothing to flag.                                                                                                                        |

A check that failed outright shows **Couldn't check** with the reason. When any check is partial or failed, a warning above the groups lists them, so an empty section is read as unconfirmed rather than clean. Selecting a row, or its **More Info** action, opens every field of that record, including detail the columns leave out.

{% hint style="danger" %}
Most checks depend on the unified audit log. When it is disabled for the tenant, the warning above the groups says so and the checks that read from it come back empty rather than clean. An empty result in that state means nothing was available to search, not that nothing happened.
{% endhint %}

Every check covers the seven days before the analysis ran, or 30 days for a tenant with Entra ID P1 or P2, whose sign-in and audit logs are kept that long. The exceptions are the MFA methods, the Intune and registered device lists, the delegations, consents and add-ins, and the trusted and blocked sender lists, which show the account's current state regardless of age. Nothing is cut to a row count: every list is read to the end of the window, and a check that could not read its whole window says so. The **Report check** column gives the number each finding carries in the [PDF report](case.md#pdf-report).

### Attacker IPs & activity

This group opens the findings with which addresses are the attacker's and, item by item, what was done from them. Activity from addresses judged Compromised, Likely attacker, Suspicious or Unknown is itemised; activity from the user's own addresses stays as counts under the other groups.

| Finding                              | What it shows                                                                                                                                                                                                                                                      |
| ------------------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| IP addresses behind this case        | Every address with its verdict, score, reasons, location, network, sign-in and activity counts, and when it was first and last seen. The summary line counts each verdict and says how many investigator overrides are applied. See [#ip-verdicts](case.md#ip-verdicts "mention"). |
| Mail the attacker touched            | Messages opened, folders synced whole by a desktop client, and mail deleted, moved or sent, with the subject and folder where known, and the mailbox it happened in.                                                                                                  |
| Files the attacker touched           | OneDrive and SharePoint files downloaded, opened, uploaded or deleted, and searches run, plus the sharing links created in the window and who opened them.                                                                                                             |
| Microsoft Forms                      | Forms created, edited or shared from attacker-side addresses, and how far each one reached (responses, anonymous responses and views, and whether Microsoft flagged it as phishing). A form built from a compromised account is a common credential-phishing lure.    |
| Other mailboxes this account reaches | Every mailbox the account has delegate access to, where that access is known from, whether it was granted in the window, and what was opened, synced or sent in it from attacker-side addresses.                                                                     |

Only addresses judged Compromised or Likely attacker count towards the group's flags and the threat score. Suspicious and Unknown addresses are listed for you to review, not treated as proven.

No API removes a single Microsoft Form, so when a form is flagged the finding shows how to remove it instead, with links to **Defender alerts** and **Microsoft Forms**: if Microsoft flagged the form as phishing, open its alert in Microsoft Defender, choose **Review this form**, then **Confirm phishing** and **Delete form**. Otherwise, after the password reset, sign in to Microsoft Forms as the account and delete the form or turn off **Accept responses**, and warn anyone who responded.

### IP verdicts

Every address seen in the case, on a sign-in or on an audited action, is judged as the attacker's, the user's or a service's. The verdict appears in the **IP addresses behind this case** list and on each sign-in and activity row that came from the address, so you can tell at a glance which rows were the user and which were not.

| Verdict         | Meaning                                                                                                                                                                           |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Compromised     | Decided outright: you marked the address as compromised for this case, or it is blocked on CIPP's [IP Allow/Block List](../../../tools/tenant-tools/geoiplookup.md).              |
| Likely attacker | The evidence points strongly at the attacker.                                                                                                                                     |
| Suspicious      | Some evidence against the address, not enough to call it the attacker's, or you marked it suspicious for this case. An address with only failed sign-ins or unfinished self-service password resets never goes higher than this. |
| Unknown         | Not enough evidence either way.                                                                                                                                                   |
| Likely user     | The evidence points at the user, for example an address they regularly signed in from before the window.                                                                         |
| Safe            | Decided outright: you marked the address as safe for this case, or it is trusted on CIPP's IP Allow/Block List.                                                                   |
| Service         | A Microsoft service address the user never signed in from, or an address whose only sign-ins or actions came from CIPP or partner delegated administration rather than the user. |

Each address carries a score built from weighted reasons, and each reason is listed with the points it added or took away. Reasons that count against an address include flagged activity from it, a hosting, proxy or VPN network, a location outside the usage location, never having been used by the user before the window, a risky or scripted sign-in, a failed sign-in that got past the password and was stopped by MFA or Conditional Access (with no successful sign-in from the address), and other accounts appearing on it only during the window. Reasons that count in its favour include the user's regular address, network or location before the window, a compliant device, colleagues using it before the window (an office or VPN exit) and a trusted named location. Entries on the Exchange tenant allow/block and connection-filter lists nudge the score without deciding it. To tell a shared office or VPN address from an attacker's, the run also looks at the sign-ins of a small random sample of the user's colleagues. An address that shares a sign-in or mailbox session with a likely-attacker address is pulled towards the attacker too, because one session moving between addresses is one actor.

A user on an approved trip is not penalised for being abroad. When [vacation mode](../vacation-mode/README.md) scheduled a travel policy for the user, a sign-in or action from one of the trip's countries while the trip lasted does not count as outside the usage location or as a new country, and it is left out of the foreign sign-in and activity counts in the threat score. The address shows **Approved travel** among its reasons. Everything else about it is still judged, so a VPN or hosting network, a risky sign-in or flagged activity from the destination still counts.

The address of a technician who ran or reviewed the case counts strongly towards the user's side, since it is most likely the partner's own, but it is still judged rather than cleared outright.

### Access & identity

How the account was reached and who can sign in as it now. The group opens with the location comparison described under [Location Analysis](case.md#location-analysis).

| Finding                              | Report check | What it shows                                                                                                                                                                                                                                                                                                                     |
| ------------------------------------ | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Interactive sign-ins                 | 10           | The user's sign-ins in the window with the application, result, IP address and its verdict, country, and city, and whether the location is outside the usage location. Flagged for successful sign-ins from outside the usage location.                                                                                          |
| Non-interactive sign-ins (token use) | 19           | The user's token refreshes and background token use in the window, with the resource and token type, compared against the usage location in the same way. Stolen tokens and adversary-in-the-middle sessions show up here rather than in the interactive log.                                                                     |
| MFA methods                          | 6            | The authentication methods registered on the account, other than its password, with the method type, name, and registration date. Methods registered in the window are marked and flagged. An account with no methods at all is called out rather than shown as an empty list, since an attacker may have removed them.            |
| Identity Protection                  | 21           | Whether Entra ID Protection lists the user as risky, at what level and in what state, with the risk detections raised during the window. Needs Entra ID P2. When the user is listed, **Dismiss risk in Identity Protection** clears it after a confirmation; do this only once the account is contained and the activity explained. |
| Entra registered devices             | 18           | Entra devices registered to the user, with those registered during the window flagged. A device registered during the window can be an intruder's virtual machine or phone, and a route to Windows Hello for Business persistence.                                                                                               |
| Intune-managed devices               | 9            | Every Intune-managed device enrolled under the account, flagged when enrolled in the window. Each row carries the device actions described under [Intune Device Actions](case.md#intune-device-actions).                                                                                                                        |

### Location Analysis

The foreign flags across the case come from one comparison: the account's **usage location** (the two-letter country code assigned in Entra ID, usually for licensing) held against where activity actually came from. The top of the **Access & identity** group shows the **Usage location**, the **Sign-in countries** with a count for each, and the **Activity outside usage location** (successful sign-ins, and rule, safelist and sharing changes and sent mail).

* Sign-ins carry their own location in the sign-in log, so those need no lookup.
* The client IPs behind inbox rule changes, safelist changes, sharing changes, and sent messages are geo-located.
* A row only counts as foreign when both sides are known. No assigned usage location, an IP that cannot be located, or a private address means the row is left unflagged, not counted against the user.
* Foreign sign-ins are split into successful and failed. Failed attempts from other countries are the constant background of password spray and are listed for context only; a successful foreign sign-in is the one that proves access and feeds the threat score.

When the account has no usage location assigned, **Usage location** reads **not set** and the sign-in countries are still listed for manual review.

{% hint style="warning" %}
Usage location is an administrative setting, not a statement of where the user works. Travel, VPN egress points, and mobile carrier routing all produce foreign rows on healthy accounts, and a usage location that was never set correctly produces them permanently. A foreign sign-in is a prompt to check with the user; a rule or safelist change from a foreign IP is much harder to explain innocently.
{% endhint %}

### Intune Device Actions

Each row under **Intune-managed devices** carries its own actions, so a suspect device can be dealt with without leaving the investigation.

| Action                          | Description                                                                             |
| ------------------------------- | --------------------------------------------------------------------------------------- |
| View Device                     | Opens the device's page within CIPP.                                                    |
| View in Intune                  | Opens the device in the Microsoft Intune admin center in a new tab.                     |
| Retire device                   | Removes company data and the Intune management profile, leaving personal data in place. |
| Wipe device (remove enrollment) | Returns the device to factory settings, removing all data and the Intune enrolment.     |

{% hint style="danger" %}
**Wipe device (remove enrollment)** is a full factory wipe, not the lighter wipe that keeps user or enrolment data. It cannot be undone, and it will take the device out of service for whoever is holding it. Confirm the device is genuinely the intruder's before running it.
{% endhint %}

**Retire device** and **Wipe device (remove enrollment)** both ask for confirmation first and need write permission for device management. The device list is part of the stored case, so it does not change afterwards; run a new investigation to see the result.

### Persistence

Footholds that survive a password reset.

| Finding              | Report check | What it shows                                                                                                                                                                                                                                                                                                                                                                                  |
| -------------------- | ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Inbox rules          | 1            | The inbox rules currently on the mailbox, each with its risk and the reasons for it, and the latest audited change to it: what changed, who made it (and whether that was the user, a partner or CIPP), when, and from which IP and country. A rule is suspicious when it forwards or redirects outside the tenant, moves mail to RSS Feeds, or hides mail (deletes it or moves it to a low-visibility folder such as Archive or Junk) and also acts on all incoming mail, targets financial or security keywords (invoice, payment, hacked, phishing...), or has a blank or punctuation-only name. An ordinary delete or archive rule is listed with its reasons but not flagged. The rule changes in the window follow in their own list. |
| Mailbox delegations  | 12           | Every delegation on the mailbox: FullAccess, SendAs, SendOnBehalf, Calendar and Inbox folder permissions, and resource delegates. A trustee that is a guest, an address outside the tenant's accepted domains, the Default/Anonymous principal with any rights on the Inbox, or with write rights on the Calendar (everyone reading a calendar is a common setting), is flagged, as is any delegation granted in the window, whatever the trustee.                        |
| Application consents | 13           | The applications this user has consented to and the enterprise-app roles assigned to them, with the client application's publisher and verification state. A consent is flagged when the application matches the CIPP known-malicious catalogue or the Huntress rogue-apps feed, or carries a high-risk delegated scope (mail, files, directory, `offline_access`) from an unverified, non-Microsoft publisher and the application first appeared in the tenant during the window. Older high-risk consents are listed as Review. |
| Mailbox add-ins      | 15           | The add-ins available to the mailbox. Enabled, user-installed add-ins from a non-Microsoft provider that were side-loaded rather than installed from the Microsoft Marketplace are flagged; an add-in can read and send mail on the user's behalf.                                                                                                                                                                                                                         |
| New applications     | 3            | Every application in the tenant, of any age, that matches CIPP's catalogue of known-malicious applications, named with its catalogue entry and source, followed by the service principals registered during the window. A catalogue match raises a warning, because consent-based access survives a password reset.                                                                      |

{% hint style="info" %}
Inbox rules carry no timestamp of their own, so a rule's latest change is found by matching its name against the audit events in the window. Rules changed from the Outlook client are recorded without a rule name, so a rule altered that way shows no latest change even though the change appears in the rule changes list.
{% endhint %}

### Mail manipulation

Bending mail flow: forwarding, safelists, transport rules and mailbox permissions.

| Finding                    | Report check | What it shows                                                                                                                                                                                                                                                                                                                                                                           |
| -------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Mailbox state              | 12           | **Forwarding**, **Automatic reply** (state and audience only; the reply text is never read), **Protocols enabled**, **SMTP AUTH disabled** and **Mailbox auditing**. Flagged when mail is forwarded or an automatic reply is on.                                                                                                                                                         |
| Trusted & blocked senders  | 8            | The mailbox's own trusted and blocked sender and domain lists, and the changes to them in the window, each with who made it, the IP address and its country. Any change in the window is flagged.                                                                                                                                                                                         |
| Transport rules            | 14           | Every current tenant-wide rule that diverts mail (BCC, copy, redirect, added recipients, moderation, outbound connector), whatever its age, plus rules with a suppression action (delete, quarantine, spam score, header changes) that changed in the window, each with its latest change and who made it from where. Changes to rules that are not flagged now are listed below. Changes that set a diversion or suppression action are flagged. |
| Mailbox permission changes | 4            | Mailbox permission and delegation changes across the tenant, with who made the change, the operation, and the rights involved. Covers permissions being added or removed, calendar delegation updates, and folder permission grants. Changes that target the investigated mailbox are flagged.                                                                                           |

### Exfiltration & spread

What left the mailbox and who was hit.

| Finding                  | Report check | What it shows                                                                                                                                                                                                                                                                                                                                                                                                               |
| ------------------------ | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Sent messages            | 5            | Messages sent by the mailbox during the window, from the message trace, with the subject, recipient, delivery status, time, the originating IP address, and its country. **Repeated subjects** and **Send bursts** list the mass-mail patterns: a subject sent as five or more separate messages or reaching twenty or more recipients, and bursts of ten or more messages or thirty or more recipients inside ten minutes. |
| Sharing links            | 11           | Every OneDrive and SharePoint sharing link the account created or changed during the window, with the file, who it was shared with, and the IP address it was done from. Anonymous links are flagged, because anyone holding the URL can open them and they give an intruder a data feed that survives a password reset.                                                                                                  |
| Mailbox activity         | 20           | Counts of the user's mailbox operations, bucketed by operation, client IP and application: item accesses, hard and soft deletes, sends, and messages sent as or on behalf of the user by someone else. Only counts are kept; no item, subject or folder is read. Hard deletes above the threshold are flagged. Item-access records need Purview Audit (Premium).                                                             |
| Received mail & Defender | 16           | Phishing-shaped mail delivered to the user during the window, from message-trace metadata only, with the sender, subject, reason and delivery status. Subjects are matched against five phishing patterns (urgency, account verification, suspension, prizes, invoices), and sender domains within one or two character edits of one of the tenant's own domains are flagged as look-alikes. Where Defender for Office 365 Plan 2 is licensed, its detections for the recipient are listed under **Defender for Office 365 detections**, and the ones that reached the mailbox are flagged. |

### Tracing a sender's spread

**Trace a sender's spread** on the **Received mail & Defender** finding, and **Who else got this email?** on each of its rows, list the recipients of a sender (optionally narrowed to a subject) from message-trace metadata, split into internal and external, so the reach of a phish is known before anyone starts cleaning up. CIPP does not search or purge mailbox content.

### Blast radius · tenant

Tenant-wide signals that outlast the one mailbox.

| Finding                                       | Report check | What it shows                                                                                                                                                                                                                                                                                                                                 |
| --------------------------------------------- | ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Other accounts the attacker addresses reached | None         | Every other account in the tenant that signed in or acted from an address judged Compromised or Likely attacker. An account with a successful sign-in or any recorded action is marked as reached and flagged; failed sign-ins alone are an attempt. Suspicious and Unknown addresses are left out, so a shared office exit does not send you after the user's colleagues. |
| Partner and CIPP actions on this account      | None         | Every audited change in the case made by a partner identity acting over GDAP (this partner or another) or by CIPP itself, gathered from the directory audit and the rule, safelist, sharing, permission, transport-rule and mailbox activity findings. Partner identities are named by their partner tenant where they belong to this partner, and each source table carries the same **ActorKind** column. Routine MSP work reads as such, and anything a partner identity did that the investigation did not expect stands out. |
| Recently added users                          | 2            | Accounts created in the tenant during the window, with their type and creation date.                                                                                                                                                                                                                                                         |
| Recent password changes                       | 7            | Accounts across the tenant whose password changed during the window, with the change time.                                                                                                                                                                                                                                                   |
| Entra directory audit                         | 17           | Directory audit events that targeted, or were initiated by, the user during the window, with who did it and from where. Security-info registration, application consent, service-principal creation, device registration, password and token events and role changes are flagged. A plain user update is flagged only when it changes sign-in methods or the recovery email, and not when the MFA service refreshes an existing Authenticator's device token. It overlaps the findings above on purpose: use it to date and attribute them, not as separate incidents. |

Select **Investigate** on one or more rows of **Other accounts the attacker addresses reached** to queue a new investigation for each account. Each case appears on the [Business Email Compromise](README.md) page as it finishes.

{% hint style="info" %}
**Recently added users**, **Recent password changes** and **Mailbox permission changes** are tenant-wide rather than scoped to this user, and **New applications** sweeps the whole tenant for catalogue matches. That is deliberate: an intruder who has taken one mailbox often leaves traces elsewhere, so a new account or an unfamiliar application appearing in the same window is worth knowing about even though it has nothing to do with the mailbox in front of you.
{% endhint %}

## Remediation taken and attack timeline

Below the findings, two collapsible cards round off the case. Both start open.

* **Remediation taken** lists every containment run on the case, newest first, with when it ran, who ran it and the result for each action and target. It appears once containment has run at least once.
* **Attack timeline** shows the case's correlated events over time, with the likely start of compromise marked. The toggle switches between **Timeline** and **Correlation graph**, which groups the events by attacker source and the accounts it reached. **Full screen** opens the same view across the whole screen, where the graph has room to spread out.

## Reviewing IP verdicts

**Review IPs** opens a drawer with one card per address in the case. Each card shows the address, its verdict, its score, its location and network, and every reason behind the score with the points it carried. Red reasons push towards the attacker, green ones towards the user. An address decided by you or by the IP Allow/Block List says what decided it.

Beside each card:

| Field   | Description                                                                                                                             |
| ------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Verdict | **Auto** keeps the verdict the case calculated. **Safe**, **Suspicious** or **Compromised** decides the address for this case, whatever its score says. **Suspicious** keeps it listed for review without counting it as the attacker's. |
| Note    | Why you decided it. Greyed out while the verdict is **Auto**.                                                                           |

**Re-run with these verdicts** re-judges every address with your decisions and replaces the verdicts, the attacker activity, the delegated mailboxes and the threat score. The rest of the case, including its analysis window, stays as it was. The re-run happens in the background, with its progress shown in the drawer, and the case refreshes when it finishes. The button is greyed out until at least one address is set to **Safe**, **Suspicious** or **Compromised**, and while the choices match the ones the case already uses.

With **Remember for this tenant (CIPP IP list)** switched on, the addresses you set to **Safe** are also added to CIPP's [IP Allow/Block List](../../../tools/tenant-tools/geoiplookup.md) as trusted, and the ones set to **Compromised** as blocked, each noted with the case id, so later cases for the tenant start from your decision. Addresses set to **Suspicious** apply to this case only. The switch only appears for users who can change CIPP settings.

## Containment

**Contain user** opens a drawer of selectable actions. The actions switched on in [BEC Remediation Defaults](../../../cipp/settings/bec-remediation.md) start selected; out of the box that is reset password, block sign-in, revoke sessions, remove MFA methods, disable inbox rules and block legacy mailbox protocols. The rest are off until you switch them on. Actions that act on specific things, such as consents, delegations, rules, add-ins and devices, get a picker filled from the case's findings, with the flagged items preselected, so what you saw in the findings is what gets contained.

| Action                                   | Impact          | What it does                                                                                                                                                                                                                               |
| ---------------------------------------- | --------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Reset password                           | Critical        | New random password (shown once, or as a PwPush link), change required at next sign-in.                                                                                                                                                    |
| Block sign-in                            | Critical        | Disables the account. A directory-synced account must also be disabled on-premises or the next sync re-enables it; the result says so.                                                                                                     |
| Revoke sessions                          | High            | Invalidates every refresh token.                                                                                                                                                                                                           |
| Remove MFA methods                       | High            | Every method, or only the ones picked.                                                                                                                                                                                                     |
| Revoke application consents              | Critical        | Deletes the picked consent grants and app-role assignments (flagged ones by default).                                                                                                                                                      |
| Disable rogue applications tenant-wide   | Critical        | Disables the service principal of every application that matched the rogue-app catalogues, for all users. Reversible from the enterprise applications page.                                                                                |
| Disable inbox rules                      | High            | All rules except the junk and out-of-office system rules, or only the ones picked.                                                                                                                                                         |
| Clear mailbox forwarding                 | High            | Removes the forwarding address and SMTP forwarding address.                                                                                                                                                                                |
| Turn off automatic replies               | Medium          | Disables the out-of-office reply.                                                                                                                                                                                                          |
| Remove mailbox delegations               | Critical        | Removes the picked FullAccess, SendAs, SendOnBehalf, folder and resource-delegate permissions (flagged ones by default).                                                                                                                   |
| Disable transport rules                  | Critical        | Disables the picked tenant-wide rules (by default the flagged rules changed in the window). Affects every mailbox.                                                                                                                         |
| Disable mailbox add-ins                  | Medium          | Disables the picked add-ins for this mailbox.                                                                                                                                                                                              |
| Block legacy mailbox protocols           | High            | Turns off EWS, IMAP, POP, ActiveSync and SMTP AUTH by default; OWA, MAPI and ECP can be added.                                                                                                                                             |
| Block / remove mobile device partnerships | High           | Blocks the picked ActiveSync devices, or deletes the partnerships so they must pair again.                                                                                                                                                 |
| Disable / delete registered devices      | High / Critical | Disables or deletes the picked Entra devices (those registered in the window by default).                                                                                                                                                  |
| Targeted Conditional Access policy       | High            | A policy for this user only requiring MFA (optionally plus a compliant device) for every app, enabled or report-only, removed automatically after the chosen hours.                                                                        |
| Disable OneDrive sharing                 | Medium          | Sets the user's OneDrive sharing to disabled. Existing links are not removed.                                                                                                                                                              |
| Block phishing senders tenant-wide       | Medium          | Adds the phishing-shaped senders that reached this mailbox, from the received-mail findings, to the Tenant Allow/Block List as blocked senders for every mailbox. Reversible from the Tenant Allow/Block List page.                         |
| Remove OneDrive/SharePoint sharing links | High            | Deletes the anyone and company-wide sharing links the user created in the window, from the sharing-change findings. Unlike disabling sharing, this revokes links that already exist. A removed link cannot be restored, only re-created.    |

The flow is deliberate:

1. Each selected action shows the targets it will act on, defaulting to the case's flagged findings; adjust them in the pickers before running.
2. When any **Critical** action is selected, the drawer asks you to type the user's UPN. Nothing runs until it matches.
3. **Run containment** executes the actions in a fixed order (password, sign-in, sessions, MFA, consents, applications, rules, forwarding, auto-reply, delegations, transport rules, add-ins, protocols, devices, Conditional Access, OneDrive sharing, phishing senders, sharing links), each on its own, so one failure never stops the rest. Containment runs in the background: the drawer shows each action's progress as it completes, including the new password when **Reset password** runs, and the case refreshes when the job finishes. Every action is logged with the case id, and the outcome is recorded on the case so the **Remediation taken** card, the report and the evidence package carry it.

{% hint style="warning" %}
Removing every MFA method leaves the account with no second factor registered. Once sign-in is unblocked and the password reset, the user has to register a method again, so plan how they will do that before running the containment on someone who is not sitting next to you.
{% endhint %}

{% hint style="info" %}
The same containment runs from the audit-log alert action **Execute a BEC Remediate**. The alert rule can choose which containment actions it runs; with none chosen it runs reset password, block sign-in, revoke sessions and disable inbox rules. Alerts confirm critical actions by design, as there is no human to type the UPN, so be deliberate about which rules get it. The **NewRiskyUsers** scheduled alert has an opt-in switch that runs the default set from [BEC Remediation Defaults](../../../cipp/settings/bec-remediation.md) for users that newly appear at high risk.
{% endhint %}

## Evidence export

**Export evidence (ZIP)** in the header packages everything CIPP holds about the case so it can be handed to an insurer, a client, a forensic partner or a compliance file. The package is built from the stored case and contains:

| File                 | Contents                                                                                                                                                  |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `report-full.pdf`    | The full PDF report, rendered at export time with your instance branding.                                                                                 |
| `report-summary.pdf` | The C-suite summary PDF, rendered the same way.                                                                                                           |
| `results.json`       | The complete results of the run, exactly as the page and the report use them, including data no finding displays, such as the mobile devices attached to the mailbox. |
| `findings/*.csv`     | One CSV per finding set (inbox rules, delegations, consents, transport rules, received-mail findings, sign-ins, devices and so on). Empty sets are skipped. |
| `score.json`         | The threat score with every signal that contributed to it.                                                                                                |
| `containment.json`   | Every containment run recorded on the case, with passwords redacted.                                                                                      |
| `logbook.json`       | Every CIPP logbook entry stamped with the case id, from the moment the run was queued to the export itself.                                               |

The package is built fresh for every export and nothing is kept on the server afterwards. Downloads from the [Business Email Compromise](README.md) page produce the same package, both PDFs included. Like the run itself, the package holds metadata only.

## PDF Report

The report is built from the case on screen, so it never starts a fresh run and always reflects the same stored result the page is showing. Its cover names the user rather than the tenant, and the logo, cover image, colours, footer and watermark come from your instance branding, described in [branding.md](../../../cipp/settings/branding.md "mention"). Its detailed findings are numbered 1 through 21, matching the **Report check** column under [Findings](case.md#findings).

The preview offers two versions of the same report:

* **Full report** holds every page below, and is written to be readable by managers and end users as well as technicians, so it is suitable for attaching to a compliance record.
* **C-suite summary** holds the cover and the **Executive Summary** only, without **Remediation Taken** and **Data Source Information**, for a reader who needs the outcome rather than the evidence. Each priority action that containment has already completed is marked as done, with the date.

| Page                                    | What it contains                                                                                                                                                                                                                                                                       |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Executive Summary                       | A narrative introduction naming the user and the tenant, four headline counts (mailbox rules, permission changes, foreign sign-ins, known-malicious applications), the threat assessment with the signals that contributed to it, and **What We Found**: the case's outcome in plain terms, including how many addresses were identified as the attacker's, where they were, what the attacker did from them, and any other accounts, mailboxes or Microsoft Forms the attack reached. **Findings at a Glance** gives every check's result, with attacker addresses, what they touched and what they reached at the top, and a breakdown of the findings by attacker objective. **Priority Remediation Actions** are written from what was found, for example securing the other accounts reached, revoking risky consents or clearing forwarding. **Order of Events** puts every timestamped signal in sequence. The full report adds **Remediation Taken** (the containment already run and its results) and **Data Source Information** (audit log status, analysis period, case id, checks that could not run or returned partial data, and the assigned usage location). |
| Attacker Addresses & Activity           | Only when the case has IP verdicts. The addresses judged the attacker's or suspicious, with verdict, location, sign-ins and the strongest reasons; what was done from the attacker's addresses (emails opened, sent and deleted, and files opened); the other accounts reached from them; the other mailboxes reached through this account; and the Microsoft Forms built from them, with how far each reached and how to remove it. Suspicious addresses are listed for review only and never counted as the attacker's. |
| Understanding Business Email Compromise | A plain-language explanation of what a compromise is, how accounts are usually taken, and why the investigation was run. Written for the user or their manager rather than the technician.                                                                                             |
| Detailed Findings                       | Checks 1 through 21, each under a short explanation of why that check matters.                                                                                                                                                                                                          |
| Recommendations                         | Six immediate containment steps, six longer-term prevention measures, and five points to pass to the user.                                                                                                                                                                             |
| Compliance & Documentation              | How the investigation maps onto ISO 27001, CMMC Level 2, SOC 2 Type II, NIST CSF and GDPR, an audit trail block with the investigation details, a **Findings Summary** listing every count, and retention guidance.                                                                    |

The **Threat Assessment** banner on the executive summary shows the same level and score as the page header, built as described under [Threat Score](case.md#threat-score).

### What the Report Leaves Out

Each section stops at a fixed number of rows and says how many were left off, so a truncated section is visible as truncated. The counts in **Findings Summary** on the last page always carry the full totals, and the evidence export has the complete set.

| Section                                        | Rows shown                |
| ---------------------------------------------- | ------------------------- |
| Mailbox rules                                  | 10                        |
| Rule changes                                   | 10                        |
| Recently created users                         | 8                         |
| New applications                               | 6                         |
| Known-malicious applications in the tenant     | 6                         |
| Mailbox permission changes                     | 5                         |
| Sent messages                                  | 10                        |
| Repeated subjects                              | 5                         |
| Send bursts                                    | 5                         |
| MFA devices                                    | 5, newest first           |
| Password changes                               | 5                         |
| Trusted and blocked senders                    | 15 of each                |
| Safelist changes                               | 10                        |
| Sharing changes                                | 10                        |
| Intune devices                                 | 5, newest enrolment first |
| Foreign sign-ins                               | 10                        |
| Flagged mailbox delegations                    | 10                        |
| Flagged application consents                   | 10                        |
| Flagged transport-rule changes                 | 5                         |
| Flagged transport rules                        | 5                         |
| Received-mail findings                         | 8                         |
| Delivered Defender threats                     | 5                         |
| Flagged directory-audit events                 | 8                         |
| Attacker and suspicious addresses              | 15                        |
| Mail and files touched from attacker addresses | 10 of each                |
| Other accounts reached                         | 15                        |
| Other mailboxes reached                        | 10                        |
| Microsoft Forms from attacker addresses        | 10                        |
| Order of events                                | 40                        |

{% include "../../../../../.gitbook/includes/feature-request.md" %}
