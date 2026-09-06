---
description: Single pane of glass review of common Indicators of Compromise (IoC)
---

# Compromise Remediation

This page gathers the signals worth checking when a mailbox is suspected of being compromised, so an investigation does not mean opening the Entra, Exchange, and Purview portals in turn. Opening the page starts an analysis of the user, and each check appears as a collapsible card with a count of what it found. A count is a prompt to look, not a verdict.

{% hint style="warning" %}
Nothing on this page is proof of a compromise. The checks surface the information that usually matters during an investigation, and several of them return results on perfectly healthy accounts. Read the findings alongside what you already know about the user and the tenant.
{% endhint %}

## Running the Analysis

Nothing runs when the page opens: it loads the user's run history and shows the latest run, or an empty status card with the start button when there is none. Starting a run queues a background job. The status card then shows whether the job is still **queued** (no worker has picked it up yet) or **running**, which phase it is in, and each phase's outcome as it completes - the same live progress the SharePoint template deployment uses. A run usually takes a few minutes; a tenant with a lot of log data can take up to ten. A run that makes no progress for twenty minutes - typically because the background worker restarted - is marked failed the next time the page polls it, with the reason shown; start a new run. Every run is kept as a **case** with its own id (`BEC-<timestamp>-<suffix>`), so returning to the page shows the user's latest run rather than starting a new one, and the **Run history** card lists every earlier run with its scope, threat level and score. Select a past run to view it exactly as it was collected; delete a run to remove it and its evidence permanently. The same history for every user, and every tenant, is on the [BEC Reports](../../../reports/bec-reports.md) page.

Every run is the full investigation: checks 1 to 21 below - the classic signals plus the mailbox delegation inventory and forwarding, auto-reply and protocol state, the user's own application consents, transport rules, mailbox add-ins, phishing-shaped received mail and Defender verdicts, the Entra directory audit, registered devices, non-interactive sign-ins, mailbox activity counts and Identity Protection state.

Runs can also be queued for many users at once. Select the users on the [Users](../README.md) page and choose **Run BEC check**, pick the scope, and one run per user (at most fifty per request) is queued as a single job that the Queue page tracks. Each run is a separate case and shows up on the [BEC Reports](../../../reports/bec-reports.md) page and in the user's own run history as it completes.

Everything collected is metadata: audit records, sign-ins, directory audits, message-trace headers, permissions, consents, rules and devices. No message body, attachment or file content is ever read or stored, which keeps the investigation inside what a partner relationship permits.

The **Log information** card at the top of the checks reports whether the audit log extraction succeeded, when the data was pulled, and which case and scope the page is showing. It is the first thing to read, because the outcome shapes everything below it. Each check card also carries a **Partial** or **Failed** chip when its collector hit a paging cap or could not read its source; hover it for the reason. A partial or failed check is reported as such rather than shown as clean.

{% hint style="danger" %}
Most checks depend on the unified audit log. When it is disabled for the tenant, the Log information card says so and the checks that read from it come back empty rather than clean. An empty result in that state means nothing was available to search, not that nothing happened.
{% endhint %}

## Checks

Every check covers the seven days before the analysis ran, apart from the MFA device list, the Intune device list, and the trusted and blocked sender lists, which show the account's current state regardless of age, and the sign-in list, which is simply the last fifty sign-ins however old they are.

| Check                               | What it looks for                                                                                                                                                                                                                                                                                                                                                                                                                                                                  |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Check 1: Mailbox Rules              | The inbox rules currently on the mailbox, and any rule created, changed, or removed in the last seven days. A rule that moves mail into an `RSS` folder raises a potential breach message, as it is a long-standing trick for hiding replies. Rules whose names match a recent audit event are marked as changed in the last seven days and sorted to the top. Each change lists the IP address it was made from and, where the IP can be located, the country.                    |
| Check 2: Recently added users       | Accounts created in the tenant during the window, listed with their creation date.                                                                                                                                                                                                                                                                                                                                                                                                 |
| Check 3: New Applications           | Service principals registered during the window, plus every application in the tenant, of any age, that matches CIPP's catalog of known-malicious applications. A catalog match is sorted to the top, named with its catalog entry, and raises a potential breach message, because consent-based access survives a password reset.                                                                                                                                                 |
| Check 4: Mailbox permission changes | Mailbox permission and delegation changes across the tenant, listed with who made the change, the operation, and the rights involved. Covers permissions being added or removed, calendar delegation updates, and folder permission grants. Changes that target the investigated mailbox are flagged and sorted to the top.                                                                                                                                                        |
| Check 5: Sent Messages              | Messages sent by the mailbox during the window, from the message trace, with the subject, recipient, delivery status, time received, the originating IP address, and the country that IP locates to. The check also looks for mass-mail patterns: a subject sent as five or more separate messages or reaching twenty or more recipients, and bursts of ten or more messages or thirty or more recipients inside ten minutes. Both are how a compromised mailbox spreads phishing. |
| Check 6: MFA Devices                | The authentication methods registered on the account, other than its password, listed with the method type, name, and registration date. Methods registered in the last seven days are flagged and sorted to the top, and an account with no methods at all is called out rather than shown as an empty list.                                                                                                                                                                      |
| Check 7: Password Changes           | Accounts across the tenant whose password changed during the window, listed with the change time.                                                                                                                                                                                                                                                                                                                                                                                  |
| Check 8: Trusted & Blocked Senders  | The mailbox's own trusted and blocked sender and domain lists, along with any changes to them in the last seven days. Each change lists the IP address it was made from and its country. If the lists cannot be read, the card says so in red instead of presenting an empty list as clean.                                                                                                                                                                                        |
| Check 9: Intune Devices             | Every Intune-managed device enrolled under the account, newest enrolment first. The card's count is the number enrolled in the last seven days rather than the total, so a zero here still leaves a device list worth reading. A device standing up during the window can mean an intruder enrolling a virtual machine or personal endpoint under the identity, which is also a route to registering Windows Hello for Business as a persistence mechanism.                        |
| Check 10: Sign-in Locations         | The user's last fifty sign-ins with the application, result, IP address, country, and city, compared against the account's assigned usage location. The card's count is the number of foreign data points found across sign-ins, rule changes, safelist changes, sharing changes, and sent mail. See [#location-analysis](bec.md#location-analysis "mention") below.                                                                                                               |
| Check 11: Sharing Links             | Every OneDrive and SharePoint sharing link the account created or changed during the window, with the file, who it was shared with, and the IP address it was done from. Anonymous links are called out separately, because anyone holding the URL can open them and they give an intruder a data feed that survives a password reset.                                                                                                                                             |

The full analysis adds the following checks.

| Check                                  | What it looks for                                                                                                                                                                                                                                                                                                                                                                                    |
| -------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Check 12: Mailbox state & delegations  | The mailbox's forwarding address, automatic-reply state (state, schedule and audience only; the reply text is never read), enabled protocols and auditing, plus every delegation on it: FullAccess, SendAs, SendOnBehalf, Calendar and Inbox folder permissions, and resource delegates. A trustee that is a guest, an address outside the tenant's accepted domains, or the Default/Anonymous principal with more than availability rights is flagged, as is any delegation whose grant appears in the window's audit log (check 4), whatever the trustee. |
| Check 13: Application consents         | The applications this user has consented to and the enterprise-app roles assigned to them, with the client application's publisher and verification state. A consent is flagged when the application matches the CIPP known-malicious catalog or the Huntress rogue-apps feed, or carries a high-risk delegated scope (mail, files, directory, `offline_access`...) from an unverified, non-Microsoft publisher. Consent survives a password reset. |
| Check 14: Transport rules              | Tenant-wide transport rules created, changed, enabled, disabled or removed during the window, attributed to the administrator and IP that made the change, flagged when the change set a diversion or suppression action (BCC, redirect, delete, quarantine, spam score). The current rules are listed too: any rule with a diversion action (BCC, copy, redirect, added recipients, moderation, outbound connector) whatever its age, and rules with a suppression action (delete, quarantine, spam score, header changes) only when they changed in the window - a description alone never flags a rule - with the tenant's total rule count.       |
| Check 15: Mailbox add-ins              | The add-ins available to the mailbox. Enabled, user-installed add-ins from a non-Microsoft provider are flagged; an add-in can read and send mail on the user's behalf.                                                                                                                                                                                                                              |
| Check 16: Received mail                | Mail delivered to the user during the window, from message-trace metadata only: sender, subject, status, size and originating IP. Subjects are matched against five phishing patterns (urgency, account verification, suspension, prizes, invoices), and sender domains within one or two character edits of one of the tenant's own domains are flagged as look-alikes. Where Defender for Office 365 Plan 2 is licensed, its analysed-email verdicts for the recipient are added, with the messages that reached the mailbox called out. |
| Check 17: Entra directory audit        | Directory audit events that targeted, or were initiated by, the user during the window, with who did it and from where. Security-info registration, application consent, service-principal creation, device registration, password and token events and role changes are flagged.                                                                                                                 |
| Check 18: Registered devices           | Entra devices registered to the user, with those registered during the window flagged. A device registered during the window can be an intruder's virtual machine or phone, and a route to Windows Hello for Business persistence.                                                                                                                                                                |
| Check 19: Non-interactive sign-ins     | The user's most recent non-interactive sign-ins (token refreshes and background token use), compared against the usage location like Check 10. Stolen tokens and adversary-in-the-middle sessions show up here rather than in the interactive log.                                                                                                                                                  |
| Check 20: Mailbox activity             | Counts of the user's mailbox operations from the unified audit log, bucketed by operation, client IP and application: item accesses, hard and soft deletes, sends, and messages sent as or on behalf of the user by someone else. Only counts are kept; no item, subject or folder is read. Hard deletes above the configured threshold are flagged. Item-access records need Purview Audit (Premium). |
| Check 21: Identity Protection          | Whether Entra ID Protection lists the user as risky, at what level and in what state, with the risk detections raised during the window. Needs Entra ID P2; when it cannot be read the card says so rather than reporting the user as not risky.                                                                                                                                                    |

{% hint style="info" %}
Checks 2, 4, and 7 are tenant-wide rather than scoped to this user, and Check 3 sweeps the whole tenant for catalog matches. That is deliberate: an intruder who has taken one mailbox often leaves traces elsewhere, so a new account or an unfamiliar application appearing in the same window is worth knowing about even though it has nothing to do with the mailbox in front of you.
{% endhint %}

{% hint style="info" %}
Inbox rules carry no timestamp of their own, so a rule is marked as recently changed by matching its name against audit events from the last seven days. Rules changed from the Outlook client are recorded without a rule name, so a rule altered that way stays unmarked even though the change appears under the rule change entries.
{% endhint %}

### Location Analysis

Check 10 and the flags scattered through the other checks come from one comparison: the account's **usage location** (the two-letter country code assigned in Entra ID, usually for licensing) held against where activity actually came from.

* Sign-ins carry their own location in the sign-in log, so those need no lookup.
* The client IPs behind inbox rule changes, safelist changes, sharing changes, and sent messages are geo-located through CIPP's GeoIP service, which caches results, so repeated runs do not repeat lookups.
* A row only counts as foreign when both sides are known. No assigned usage location, an IP that cannot be located, or a private address means the row is left unflagged, not counted against the user.
* Foreign sign-ins are split into successful and failed. Failed attempts from other countries are the constant background of password spray and are listed for context only; a successful foreign sign-in is the one that proves access and feeds the threat score.

When the account has no usage location assigned, the card says the comparison is unavailable and still lists the countries seen, for manual review.

{% hint style="warning" %}
Usage location is an administrative setting, not a statement of where the user works. Travel, VPN egress points, and mobile carrier routing all produce foreign rows on healthy accounts, and a usage location that was never set correctly produces them permanently. A foreign sign-in is a prompt to check with the user; a rule or safelist change from a foreign IP is much harder to explain innocently.
{% endhint %}

### Intune Device Actions

Each row in Check 9 carries its own actions, so a suspect device can be dealt with without leaving the investigation.

| Action                          | Description                                                                             |
| ------------------------------- | --------------------------------------------------------------------------------------- |
| View Device                     | Opens the device's page within CIPP.                                                    |
| View in Intune                  | Opens the device in the Microsoft Intune admin center in a new tab.                     |
| Retire device                   | Removes company data and the Intune management profile, leaving personal data in place. |
| Wipe device (remove enrollment) | Returns the device to factory settings, removing all data and the Intune enrolment.     |

{% hint style="danger" %}
**Wipe device (remove enrollment)** is a full factory wipe, not the lighter wipe that keeps user or enrolment data. It cannot be undone, and it will take the device out of service for whoever is holding it. Confirm the device is genuinely the intruder's before running it.
{% endhint %}

**Retire device** and **Wipe device (remove enrollment)** both ask for confirmation first and need write permission for device management. Neither updates the list afterwards, so use **Refresh Data** to see the result.

{% hint style="warning" %}
If CIPP cannot read the tenant's Intune devices, the card says so in red and shows no count. That is not the same as the user having no devices, and it usually points at missing permissions or licensing rather than a clean result. Fix the underlying problem and refresh rather than reading the empty card as an all-clear. The sign-in and sender-list checks behave the same way when their sources cannot be read.
{% endhint %}

## Actions

| Action              | Description                                                                                                                                                                                                                                                                                                       |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Run investigation   | Starts a new run of all 21 checks. The earlier run stays in the history. Use it when the data on screen predates something you need to see, such as a rule created in the last few minutes or a device you have just retired. The page returns to its waiting state while the new run completes.                            |
| Contain user        | Opens the containment drawer described under [#containment](bec.md#containment "mention"): pick the actions and their targets, type the UPN for critical ones, run.                                                                                                                                  |
| Generate PDF Report | Opens a preview of a formatted report covering the findings, written to be readable by managers and end users as well as technicians, and suitable for attaching to a compliance record. **Download PDF** saves it. What the report contains is covered under [#pdf-report](bec.md#pdf-report "mention") below. |
| Download JSON       | Saves the complete analysis as a JSON file, including data the cards do not display.                                                                                                                                                                                                                              |
| Export evidence     | Builds the evidence package for the run on screen and downloads it: a ZIP holding the PDF report, the results JSON, a CSV per finding set, the containment history, every logbook entry for the case and a manifest with the SHA-256 of each file. See [#evidence-export](bec.md#evidence-export "mention").                                                          |

{% hint style="warning" %}
Removing every MFA method leaves the account with no second factor registered. Once sign-in is unblocked and the password reset, the user has to register a method again, so plan how they will do that before running the containment on someone who is not sitting next to you.
{% endhint %}

## Containment

**Contain user** replaces the fixed six-step remediation with a drawer of selectable actions. The classic six are preselected; the rest are off until you switch them on. Actions that act on specific things - consents, delegations, rules, add-ins, devices - get a picker filled from the run's findings, with the flagged items preselected, so what you saw in the checks is what gets contained.

| Action                               | Impact   | What it does                                                                                                                                                            |
| ------------------------------------ | -------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Reset password                       | Critical | New random password (shown once, or as a PwPush link), change required at next sign-in.                                                                                 |
| Block sign-in                        | Critical | Disables the account. A directory-synced account must also be disabled on-premises or the next sync re-enables it; the result says so.                                  |
| Revoke sessions                      | High     | Invalidates every refresh token.                                                                                                                                         |
| Remove MFA methods                   | High     | Every method, or only the ones picked.                                                                                                                                   |
| Revoke application consents          | Critical | Deletes the picked consent grants and app-role assignments (flagged ones by default).                                                                                    |
| Disable rogue applications tenant-wide | Critical | Disables the service principal of every application that matched the rogue-app catalogs, for all users. Reversible from the enterprise applications page.            |
| Disable inbox rules                  | High     | All rules except the junk and out-of-office system rules, or only the ones picked.                                                                                      |
| Clear mailbox forwarding             | High     | Removes the forwarding address and SMTP forwarding address.                                                                                                             |
| Turn off automatic replies           | Medium   | Disables the out-of-office reply.                                                                                                                                       |
| Remove mailbox delegations           | Critical | Removes the picked FullAccess, SendAs, SendOnBehalf, folder and resource-delegate permissions (flagged ones by default).                                                |
| Disable transport rules              | Critical | Disables the picked tenant-wide rules (by default the flagged rules changed in the window). Affects every mailbox.                                                      |
| Disable mailbox add-ins              | Medium   | Disables the picked add-ins for this mailbox.                                                                                                                            |
| Block legacy mailbox protocols       | High     | Turns off EWS, IMAP, POP and ActiveSync by default; OWA, MAPI, ECP and SMTP AUTH can be added.                                                                          |
| Block / remove mobile device partnerships | High | Blocks the picked ActiveSync devices, or deletes the partnerships so they must pair again.                                                                            |
| Disable / delete registered devices  | High / Critical | Disables or deletes the picked Entra devices (those registered in the window by default).                                                                        |
| Targeted Conditional Access policy   | High     | A policy for this user only requiring MFA (optionally plus a compliant device) for every app, enabled or report-only, removed automatically after the chosen hours.     |
| Disable OneDrive sharing             | Medium   | Sets the user's OneDrive sharing to disabled. Existing links are not removed.                                                                                           |

The flow is deliberate:

1. Each selected action shows the targets it will act on, defaulting to the run's flagged findings; adjust them in the pickers before running.
2. When any **Critical** action is selected, the drawer asks you to type the user's UPN. Nothing runs until it matches.
3. **Run containment** executes the actions in a fixed order (password, sign-in, sessions, MFA, consents, applications, rules, forwarding, auto-reply, delegations, transport rules, add-ins, protocols, devices, Conditional Access, OneDrive), each on its own, so one failure never stops the rest. Every action is logged with the case id, and the outcome is recorded on the run so the history and the evidence package carry it.

{% hint style="info" %}
The same containment runs from the audit-log alert action **Execute a BEC Remediate**. The alert rule can now choose which containment actions it runs; with none chosen it runs the four steps this action always ran (reset password, block sign-in, revoke sessions, disable inbox rules). Alerts confirm critical actions by design - there is no human to type the UPN - so be deliberate about which rules get it. The **NewRiskyUsers** scheduled alert has an opt-in switch that runs the classic six for users that newly appear at high risk.
{% endhint %}

### Purview content search and purge

The **Purview content search and purge** card is the GDAP-compatible answer to "get that phishing message out of everyone's mailbox". Enter the sender, a subject fragment and the dates, choose every mailbox or a list, and CIPP creates and starts a Purview content search. **Refresh status** shows the state and the item count per mailbox - counts only; CIPP never retrieves the messages. The **Who else received mail from this sender?** row action on the received-mail findings (and **Trace a sender's spread**) lists the recipients of a sender from message-trace metadata, split into internal and external, to decide which mailboxes the search should cover. The row actions also add the sender or its whole domain to the Tenant Allow/Block List.

Purging soft-deletes the found items through Purview. It is irreversible from CIPP and is gated two ways: only a CIPP **super admin** sees the control, and the **search name must be typed** to confirm; the status above the control shows the counts that will be purged. Purview removes at most 10 items per mailbox per purge, so repeat the search and purge until the count reaches zero.

{% hint style="warning" %}
Content search needs the CIPP-SAM service principal in a Purview role group that includes **Compliance Search** (eDiscovery Manager); purging additionally needs **Search And Purge**. Neither is granted by the CIPP-SAM setup. When the role is missing the result says exactly that rather than failing silently.
{% endhint %}

{% hint style="info" %}
The JSON export carries three data sets that no card displays: the last fifty sign-ins for the tenant as a whole (`TenantLastSignIns`), the user's single most recent sign-in, and the mobile devices attached to the mailbox. If the investigation turns on tenant-wide sign-in activity or an unrecognised mobile device, that is where to look. The Intune device list in the export also holds the manufacturer, model, owner type, and assigned user, none of which the card shows.
{% endhint %}

## Evidence export

**Export evidence (ZIP)** on the Report card packages everything CIPP holds about the case so it can be handed to an insurer, a client, a forensic partner or a compliance file, and be verified later. The package is built on the server from the stored run and contains:

| File                   | Contents                                                                                                                                                  |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `report-full.pdf`      | The full PDF report, rendered in the browser at export time with your instance branding.                                                                   |
| `report-summary.pdf`   | The C-suite summary PDF, rendered the same way.                                                                                                           |
| `results.json`         | The complete results of the run, exactly as the page and the report use them.                                                                             |
| `findings/*.csv`       | One CSV per finding set (inbox rules, delegations, consents, transport rules, received-mail findings, sign-ins, devices and so on). Empty sets are skipped. |
| `score.json`           | The threat score with every signal that contributed to it.                                                                                                |
| `containment.json`     | Every containment run recorded on the case, with passwords redacted.                                                                                      |
| `logbook.json`         | Every CIPP logbook entry stamped with the case id, from the moment the run was queued to the export itself.                                               |
| `manifest.sha256.json` | The case, tenant, user, who exported it and when, and the SHA-256 of every file above.                                                                    |

The package is built fresh for every export and streamed to your browser - nothing is stored. Each export's SHA-256, time and size are recorded on the run (the last twenty) and shown next to the button and on the [BEC Reports](../../../reports/bec-reports.md) page, so a copy received later can be checked against the export it came from. Downloads from the reports page produce the same package, both PDFs included. Like the run itself, the package holds metadata only.

## PDF Report

The report is built from the analysis already on screen, so it never starts a fresh run and always reflects the same cached result the cards are showing. Its cover names the user rather than the tenant, and the logo, cover image, colours, footer and watermark come from your instance branding, described in [branding.md](../../../../cipp/settings/branding.md "mention"). Its detailed findings use the same check numbers as the page, 1 through 11.

| Page                                    | What it contains                                                                                                                                                                                                                                                                       |
| --------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Executive Summary                       | A narrative introduction naming the user and the tenant, four headline counts (mailbox rules, permission changes, foreign sign-ins, known-malicious applications), the threat assessment, and the audit log status, analysis period, and assigned usage location.                      |
| Understanding Business Email Compromise | A plain-language explanation of what a compromise is, how accounts are usually taken, and why the investigation was run. Written for the user or their manager rather than the technician.                                                                                             |
| Detailed Findings                       | The page's checks 1 through 11 (rules, users, applications, permission changes, sent messages, authentication methods, password changes, trusted and blocked senders, Intune devices, sign-in locations, and sharing links), each under a short explanation of why that check matters. |
| Recommendations                         | Six immediate containment steps, six longer-term prevention measures, and five points to pass to the user.                                                                                                                                                                             |
| Compliance & Documentation              | How the investigation maps onto ISO 27001, CMMC Level 2, SOC 2 Type II, NIST CSF and GDPR, an audit trail block with the investigation details, a **Findings Summary** listing every count, and retention guidance.                                                                    |

### Threat Assessment

The **Threat Assessment** banner on the executive summary is a total of fixed points, one contribution per finding, regardless of how many results that finding returned. The score is computed by the backend when the run completes and stored with it, so the page's **Threat assessment** card, the report and the API all show the same number and the same list of signals that fired. The weights live in `Config/BecHeuristics.json`.

| Finding                                                          | Points |
| ---------------------------------------------------------------- | ------ |
| Identity Protection lists the user as confirmed compromised      | 5      |
| A consent to an application in the rogue-app catalogs            | 5      |
| Identity Protection lists the user at high risk                  | 4      |
| A transport rule with a diversion or suppression action changed  | 4      |
| A consent with a high-risk scope from an unverified publisher    | 3      |
| Mail received from a look-alike of one of the tenant's domains   | 3      |
| A Defender-classified threat delivered to the mailbox            | 3      |
| A successful non-interactive sign-in from outside the usage location | 3  |
| A flagged mailbox delegation (external, guest or catch-all)      | 2      |
| A flagged directory-audit event                                  | 2      |
| An Entra device registered in the window                         | 2      |
| Hard deletes above the threshold, or mailbox access from a foreign IP | 2 |
| Identity Protection lists the user at medium risk                | 2      |
| A user-installed non-Microsoft add-in                            | 1      |
| Identity Protection lists the user at low risk                   | 1      |
| A rule that moves mail to an RSS folder                          | 5      |
| An application matching the known-malicious catalog              | 5      |
| One or more inbox rules on the mailbox                           | 3      |
| One or more inbox rule changes in the window                     | 3      |
| A successful sign-in from outside the usage location             | 3      |
| A rule, safelist, sharing, or sent-mail action from a foreign IP | 3      |
| An anonymous sharing link created or changed in the window       | 3      |
| A mass-mail pattern (repeated subjects or send bursts)           | 3      |
| A permission change targeting the investigated mailbox           | 2      |
| One or more changes to the trusted or blocked senders list       | 2      |
| An MFA method registered in the window                           | 2      |
| An Intune device enrolled in the window                          | 2      |
| Permission changes elsewhere in the tenant only                  | 1      |
| One or more new applications                                     | 1      |
| More than five new users                                         | 1      |

Seven points or more reads as **High**, four to six as **Medium**, and anything below that as **Low**.

{% hint style="warning" %}
Scoring counts findings, not volume. A mailbox holding a single ordinary inbox rule already scores three, one point short of Medium, so a single unrelated finding tips it over. Forty rules score the same three points as one.
{% endhint %}

{% hint style="warning" %}
New users, new applications, and permission changes are tenant-wide checks, but each carries a single point unless a permission change targets the investigated mailbox. Tenant churn nudges the score rather than driving it. A wrongly-set usage location, on the other hand, can add three points through a perfectly normal successful sign-in, so check the assigned location before trusting a foreign-sign-in score.
{% endhint %}

{% hint style="danger" %}
Password changes carry no weight, and the MFA and Intune lists only score for registrations and enrolments inside the window; long-standing methods and devices do not move the banner however unfamiliar they look. Sent messages score only for a foreign-IP send or a mass-mail pattern. Failed sign-ins from foreign countries score nothing either: password spray hits every internet-facing tenant, so only a successful foreign sign-in counts, though the failures still show in Check 10. A Low is a summary of what scored, not an all-clear; read the checks.
{% endhint %}

### What the Report Leaves Out

Each section stops at a fixed number of rows and says how many were left off, so a truncated section is visible as truncated. The counts in **Findings Summary** on the last page always carry the full totals, and **Download JSON** has the complete set.

| Section                                    | Rows shown                |
| ------------------------------------------ | ------------------------- |
| Mailbox rules                              | 10                        |
| Rule changes                               | 10                        |
| Recently created users                     | 8                         |
| New applications                           | 6                         |
| Known-malicious applications in the tenant | 6                         |
| Mailbox permission changes                 | 5                         |
| Sent messages                              | 10                        |
| Repeated subjects                          | 5 (analysis keeps 10)     |
| Send bursts                                | 5 (analysis keeps 10)     |
| MFA devices                                | 5, newest first           |
| Password changes                           | 5                         |
| Trusted and blocked senders                | 15 of each                |
| Safelist changes                           | 10                        |
| Sharing changes                            | 10                        |
| Intune devices                             | 5, newest enrolment first |
| Foreign sign-ins                           | 10                        |

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
