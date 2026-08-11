---
description: Single pane of glass review of common Indicators of Compromise (IoC)
---

# Compromise Remediation

This page gathers the signals worth checking when a mailbox is suspected of being compromised, so an investigation does not mean opening the Entra, Exchange, and Purview portals in turn. Opening the page starts an analysis of the user, and each check appears as a collapsible card with a count of what it found. A count is a prompt to look, not a verdict.

{% hint style="warning" %}
Nothing on this page is proof of a compromise. The checks surface the information that usually matters during an investigation, and several of them return results on perfectly healthy accounts. Read the findings alongside what you already know about the user and the tenant.
{% endhint %}

## Running the Analysis

The analysis runs as a background job. The first visit queues it and the page polls until it finishes, which can take up to ten minutes on a tenant with a lot of log data. The result is then cached against the user, so returning to the page shows the earlier run rather than starting a new one.

The **Log information** card at the top of the checks reports whether the audit log extraction succeeded and when the data was pulled. It is the first thing to read, because the outcome shapes everything below it.

{% hint style="danger" %}
Most checks depend on the unified audit log. When it is disabled for the tenant, the Log information card says so and the checks that read from it come back empty rather than clean. An empty result in that state means nothing was available to search, not that nothing happened.
{% endhint %}

## Checks

Every check covers the seven days before the analysis ran, apart from the MFA device list and the Intune device list, which show the account's current registrations and devices regardless of age.

| Check                               | What it looks for                                                                                                                                                                                                                                                                                                                                                                                                                                           |
| ----------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Check 1: Mailbox Rules              | The inbox rules currently on the mailbox, and any rule created, changed, or removed in the last seven days. A rule that moves mail into an `RSS` folder raises a potential breach message, as it is a long-standing trick for hiding replies. Rules whose names match a recent audit event are marked as changed in the last seven days and sorted to the top.                                                                                              |
| Check 2: Recently added users       | Accounts created in the tenant during the window, listed with their creation date.                                                                                                                                                                                                                                                                                                                                                                          |
| Check 3: New Applications           | Service principals registered during the window, listed with their application ID and creation date.                                                                                                                                                                                                                                                                                                                                                        |
| Check 4: Mailbox permission changes | Mailbox permission and delegation changes across the tenant, listed with who made the change, the operation, and the rights involved. Covers permissions being added or removed, calendar delegation updates, and folder permission grants.                                                                                                                                                                                                                 |
| Check 5: Sent Messages              | Messages sent by the mailbox during the window, from the message trace, with the subject, recipient, delivery status, time received, and originating IP address.                                                                                                                                                                                                                                                                                            |
| Check 6: MFA Devices                | The authentication methods registered on the account, other than its password, listed with the method type, name, and registration date.                                                                                                                                                                                                                                                                                                                    |
| Check 7: Password Changes           | Accounts across the tenant whose password changed during the window, listed with the change time.                                                                                                                                                                                                                                                                                                                                                           |
| Check 8: Trusted & Blocked Senders  | The mailbox's own trusted and blocked sender and domain lists, along with any changes to them in the last seven days.                                                                                                                                                                                                                                                                                                                                       |
| Check 9: Intune Devices             | Every Intune-managed device enrolled under the account, newest enrolment first. The card's count is the number enrolled in the last seven days rather than the total, so a zero here still leaves a device list worth reading. A device standing up during the window can mean an intruder enrolling a virtual machine or personal endpoint under the identity, which is also a route to registering Windows Hello for Business as a persistence mechanism. |

{% hint style="info" %}
Checks 2, 3, 4, and 7 are tenant-wide rather than scoped to this user. That is deliberate: an intruder who has taken one mailbox often leaves traces elsewhere, so a new account or an unfamiliar application appearing in the same window is worth knowing about even though it has nothing to do with the mailbox in front of you.
{% endhint %}

{% hint style="info" %}
Inbox rules carry no timestamp of their own, so a rule is marked as recently changed by matching its name against audit events from the last seven days. Rules changed from the Outlook client are recorded without a rule name, so a rule altered that way stays unmarked even though the change appears under the rule change entries.
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

Both actions need write permission for device management, and the list does not update on its own afterwards. Use **Refresh Data** to see the result.

{% hint style="warning" %}
If CIPP cannot read the tenant's Intune devices, the card says so in red and shows no count. That is not the same as the user having no devices, and it usually points at missing permissions or licensing rather than a clean result. Fix the underlying problem and refresh rather than reading the empty card as an all-clear.
{% endhint %}

## Actions

| Action              | Description                                                                                                                                                                                                                                                                                                       |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Refresh Data        | Discards the cached result and runs the analysis again. Use it when the cached data predates something you need to see, such as a rule created in the last few minutes or a device you have just retired. The page returns to its waiting state while the new run completes.                                      |
| Remediate User      | Runs the containment steps listed on the overview card in one go: blocks sign-in, resets the password, disconnects all current sessions, removes every MFA method, disables all inbox rules, and disables OneDrive sharing. A confirmation dialog appears first.                                                  |
| Generate PDF Report | Opens a preview of a formatted report covering the findings, written to be readable by managers and end users as well as technicians, and suitable for attaching to a compliance record. **Download PDF** saves it. What the report contains is covered under [#pdf-report](bec.md#pdf-report "mention") below. |
| Download JSON       | Saves the complete analysis as a JSON file, including data the cards do not display.                                                                                                                                                                                                                              |

{% hint style="warning" %}
Removing every MFA method leaves the account with no second factor registered. Once sign-in is unblocked and the password reset, the user has to register a method again, so plan how they will do that before running the remediation on someone who is not sitting next to you.
{% endhint %}

{% hint style="info" %}
**Remediate User** does not touch the user's devices. If Check 9 has turned up an enrolment you do not recognize, retiring or wiping it is a separate decision and a separate action.
{% endhint %}

{% hint style="info" %}
The JSON export carries three data sets that no card displays: the last fifty sign-ins for the tenant, the user's most recent sign-in, and the mobile devices attached to the mailbox. If the investigation turns on sign-in origin or an unrecognized device, that is where to look. The Intune device list in the export also holds the manufacturer, model, owner type, and assigned user, none of which the card shows.
{% endhint %}

## PDF Report

The report is built from the analysis already on screen, so it never starts a fresh run and always reflects the same cached result the cards are showing. Its cover names the user rather than the tenant, and the logo, cover image, colors, footer and watermark come from your instance branding, described in [branding.md](../../../../cipp/settings/branding.md "mention").

| Page                                    | What it contains                                                                                                                                                                                                                        |
| --------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Executive Summary                       | A narrative introduction naming the user and the tenant, four headline counts (mailbox rules, permission changes, new applications, new users), the threat assessment, and the audit log status and analysis period.                     |
| Understanding Business Email Compromise | A plain-language explanation of what a compromise is, how accounts are usually taken, and why the investigation was run. Written for the user or their manager rather than the technician.                                               |
| Detailed Findings                       | The rules, users, applications, permission changes, authentication methods, password changes, trusted and blocked senders, and Intune devices, each under a short explanation of why that check matters.                                 |
| Recommendations                         | Six immediate containment steps, six longer-term prevention measures, and five points to pass to the user.                                                                                                                              |
| Compliance & Documentation              | How the investigation maps onto ISO 27001, CMMC Level 2, SOC 2 Type II, NIST CSF and GDPR, an audit trail block with the investigation details, a **Findings Summary** listing every count, and retention guidance.                      |

### Threat Assessment

The **Threat Assessment** banner on the executive summary is a total of fixed points, one contribution per finding, regardless of how many results that finding returned.

| Finding                                                    | Points |
| ---------------------------------------------------------- | ------ |
| A rule that moves mail to an RSS folder                     | 5      |
| One or more inbox rules on the mailbox                      | 3      |
| One or more inbox rule changes in the window                | 3      |
| One or more mailbox permission changes                      | 2      |
| One or more new applications                                | 2      |
| One or more changes to the trusted or blocked senders list  | 2      |
| More than five new users                                    | 1      |

Seven points or more reads as **High**, four to six as **Medium**, and anything below that as **Low**.

{% hint style="warning" %}
Scoring counts findings, not volume. A mailbox holding a single ordinary inbox rule already scores three, one point short of Medium, so a single unrelated finding tips it over. Forty rules score the same three points as one.
{% endhint %}

{% hint style="warning" %}
New users and mailbox permission changes are tenant-wide checks, so activity that has nothing to do with this mailbox can raise the level on an otherwise quiet account.
{% endhint %}

{% hint style="danger" %}
Authentication methods, password changes, sent messages and Intune devices carry no weight at all. An intruder who registers a new MFA method or enrols a device during the window does not move the banner, so read Checks 6, 7 and 9 yourself rather than treating a Low as an all-clear.
{% endhint %}

### What the Report Leaves Out

Each section stops at a fixed number of rows.

| Section                     | Rows shown                |
| --------------------------- | ------------------------- |
| Mailbox rules               | 10                        |
| Rule changes                | 10                        |
| Recently created users      | 8                         |
| New applications            | 6                         |
| Mailbox permission changes  | 5                         |
| MFA devices                 | 5                         |
| Password changes            | 5                         |
| Trusted and blocked senders | 15 of each                |
| Intune devices              | 5, newest enrolment first |

{% hint style="warning" %}
Only the rules, rule changes, users and applications sections say how many rows were left off. The others stop at the limit with nothing to show that more was found, so check the counts in **Findings Summary** on the last page against what each section lists, and use **Download JSON** for the full set.
{% endhint %}

{% hint style="info" %}
The report's check numbers run from 1 to 8 and do not line up with the page's 1 to 9, because Check 5: Sent Messages has no equivalent section in the report. If the message trace matters to the investigation, it only exists in the JSON export.
{% endhint %}

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
