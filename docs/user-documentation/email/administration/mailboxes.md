---
description: View information on all mailboxes in your Microsoft 365 tenants.
---

# Mailboxes

This page lists the Exchange Online mailboxes in the selected tenant and is the starting point for mailbox administration. Alongside creating shared mailboxes, it carries the per-mailbox actions that would otherwise need Exchange Online PowerShell: permissions, archives, holds, quotas, conversions and calendar processing.

## Action Buttons

<details>

<summary>Add Shared Mailbox</summary>

Creates a shared mailbox in the selected tenant.

| Field        | Description                                                                              |
| ------------ | ---------------------------------------------------------------------------------------- |
| Display Name | The name shown in the address list. Required.                                            |
| Username     | The part before the @ symbol. Required.                                                  |
| Domain       | The domain used after the @ symbol, chosen from the tenant's verified domains. Required. |

**Create Shared Mailbox** submits the form. Once a mailbox has been created the button changes to **Create Another Mailbox** and the form clears, keeping the domain you chose so several mailboxes can be created in succession.

</details>

## Table Details

| Column                     | Description                                                                                             |
| -------------------------- | ------------------------------------------------------------------------------------------------------- |
| Display Name               | The name shown throughout Microsoft 365 and in the address list.                                        |
| Recipient Type Details     | The kind of mailbox: `UserMailbox`, `SharedMailbox`, `RoomMailbox`, `EquipmentMailbox` and so on.       |
| UPN                        | The user principal name of the account the mailbox belongs to.                                          |
| Primary Smtp Address       | The address mail is sent from and delivered to by default.                                              |
| Additional Email Addresses | Every secondary SMTP address on the mailbox, comma separated. The primary address is not repeated here. |
| Storage Used In Bytes      | How much of the mailbox is in use, taken from Microsoft 365 usage reporting for the last seven days.    |
| Archive Enabled            | Whether an online archive exists for the mailbox.                                                       |
| Archive Size               | How much of the online archive is in use. Zero for a mailbox with no archive.                           |

{% hint style="info" %}
**Storage Used In Bytes** and **Archive Size** come from usage reporting rather than from the mailbox itself, so they are only present when the table is reading cached data.
{% endhint %}

The row flyout and the page filters expose further properties, most usefully **Auto Expanding Archive** and **Auto Expanding Archive Scope**. Auto-expanding archiving can be switched on for the whole organization or for a single mailbox, and the organization setting wins, so the scope tells you which of the two is responsible: `Organization`, `Mailbox`, or `None` when it is off.

{% hint style="warning" %}
If every mailbox reports zero storage used, an alert appears above the table. This almost always means Microsoft 365 report anonymisation is switched on for the tenant, which replaces the user principal names in usage reports with pseudonyms and stops CIPP matching the usage data back to the mailboxes. Enabling the **Enable Usernames instead of pseudo anonymised names in reports** standard turns the setting off, after which the data needs syncing again to restore the figures.
{% endhint %}

## Filters

| Filter                              | Shows                                                                                                                    |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| View User Mailboxes                 | Mailboxes belonging to a licensed user.                                                                                  |
| View Shared Mailboxes               | Shared mailboxes.                                                                                                        |
| View Room Mailboxes                 | Room resource mailboxes.                                                                                                 |
| View Equipment Mailboxes            | Equipment resource mailboxes.                                                                                            |
| View Archive-Enabled Mailboxes      | Mailboxes with an online archive.                                                                                        |
| View Auto Expanding Archive Enabled | Mailboxes with auto-expanding archiving in effect, whether that comes from the organization setting or from the mailbox. |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Bulk Add Mailbox Permissions</td><td>Grants other users access to the selected mailbox(es). <code>Full Access</code>, <code>Send As</code>, and <code>Send On Behalf</code> are each granted to their own list of users, and automapping (which makes Outlook add the mailbox on its own) is on by default for <code>Full Access</code>.</td><td>true</td></tr><tr><td>Edit permissions</td><td>Opens the <a data-mention href="../../identity/administration/users/user/exchange.md">exchange.md</a> for the mailbox's user, where existing permissions can be changed or removed.</td><td>false</td></tr><tr><td>Research Compromised Account</td><td><p>Opens the <a data-mention href="../../identity/administration/users/user/bec.md">bec.md</a> investigation for the account, which analyzes indicators of compromise:</p><ul><li>Sign-in patterns</li><li>Mail rules</li><li>Suspicious activities</li></ul></td><td>false</td></tr><tr><td>Send MFA Push</td><td>Sends a test MFA prompt to the user's registered devices.</td><td>true</td></tr><tr><td>Convert Mailbox</td><td>Converts the mailbox to a different type: <code>User Mailbox</code>, <code>Shared Mailbox</code>, <code>Room Mailbox</code> or <code>Equipment Mailbox</code>.</td><td>true</td></tr><tr><td>Enable Online Archive</td><td>Creates the online archive for the mailbox. Greyed out on a mailbox that already has one.</td><td>true</td></tr><tr><td>Set Retention Policy</td><td>Applies one of the tenant's messaging records management retention policies to the selected mailbox(es).</td><td>true</td></tr><tr><td>Enable Auto-Expanding Archive</td><td>Switches on auto-expanding archiving for the mailbox, letting the archive grow beyond its initial quota. Greyed out on a mailbox with no online archive, and cannot be undone once enabled.</td><td>true</td></tr><tr><td>Set Global Address List visibility</td><td>Hides or shows the mailbox in the Global Address List. Changes can take up to 72 hours to appear.</td><td>true</td></tr><tr><td>Start Managed Folder Assistant</td><td>Runs the managed folder assistant against the mailbox, which applies its retention settings immediately rather than waiting for the next scheduled run.</td><td>true</td></tr><tr><td>Delete Mailbox</td><td>Deletes the mailbox and the account it belongs to.</td><td>true</td></tr><tr><td>Set Copy Sent Items for Delegated Mailboxes</td><td>Controls whether mail sent as, or on behalf of, the mailbox is also saved to its Sent Items. Greyed out on anything other than a user or shared mailbox.</td><td>true</td></tr><tr><td>Set Litigation Hold</td><td>Places the mailbox on litigation hold for a number of days, or indefinitely if left blank, and can disable an existing hold. Greyed out on a mailbox whose license does not include litigation hold.</td><td>true</td></tr><tr><td>Set Retention Hold</td><td>Suspends the processing of retention policies for the mailbox, or lifts an existing retention hold.</td><td>true</td></tr><tr><td>Set Mailbox Locale</td><td>Sets the mailbox language and regional format, for example <code>en-US</code>, which also names the default folders.</td><td>true</td></tr><tr><td>Set Max Send/Receive Size</td><td>Sets the largest message the mailbox can send and receive, from 1 to 150MB. Either can be left blank to leave it unchanged.</td><td>true</td></tr><tr><td>Set Send Quota</td><td>Sets the size at which the mailbox is blocked from sending, for example <code>10GB</code>.</td><td>true</td></tr><tr><td>Set Send and Receive Quota</td><td>Sets the size at which the mailbox is blocked from both sending and receiving.</td><td>true</td></tr><tr><td>Set Quota Warning Level</td><td>Sets the size at which the user is warned that the mailbox is filling up.</td><td>true</td></tr><tr><td>Set Calendar Processing</td><td>Configures how a resource handles booking requests: automatic processing and acceptance, conflict and recurrence rules, booking window and duration limits, what is kept of the original request, and the response text sent back. Greyed out on anything other than a room or equipment mailbox.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
