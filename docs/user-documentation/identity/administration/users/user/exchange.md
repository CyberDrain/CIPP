---
description: This page displays information about the user's Exchange settings.
---

# Exchange Settings

This page brings together the mailbox side of a user's account: the mailbox's own settings, who has access to it, what it has access to, the rules and sender lists it carries, and the forwarding and automatic reply configuration. The header carries the same details as the [.](./ "mention") tab, with an **Actions** menu that acts on this mailbox.

{% hint style="info" %}
When the account has no mailbox, the page reports that rather than showing empty cards, with a **Show Details** button that reveals the underlying Exchange error. The usual cause is that the account is not licensed for Exchange Online.
{% endhint %}

## Actions

## Actions

The **Actions** menu acts on this mailbox. Some entries are greyed out rather than hidden when they do not apply, so the menu always shows the same list and the state of the mailbox decides what can be run. The whole menu is unavailable until the mailbox details have loaded.

| Action                                      | Description                                                                                                                                                                                                                                                                                                               |
| ------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Bulk Add Mailbox Permissions                | Grants other users `Full Access`, `Send As` or `Send on Behalf` on this mailbox, with an automapping option for `Full Access`.                                                                                                                                                                                            |
| Send MFA Push                               | Sends an approval request to the user's registered devices, which is a quick way to confirm you are speaking to the right person.                                                                                                                                                                                         |
| Convert Mailbox                             | Converts the mailbox to a User, Shared, Room or Equipment mailbox.                                                                                                                                                                                                                                                        |
| Enable Online Archive                       | Turns on the archive mailbox. Greyed out once the mailbox has an archive.                                                                                                                                                                                                                                                 |
| Set Retention Policy                        | Applies one of the tenant's retention policies to the mailbox.                                                                                                                                                                                                                                                            |
| Enable Auto-Expanding Archive               | Allows the archive to grow beyond its initial quota. Greyed out until the archive is enabled, and it cannot be turned off again.                                                                                                                                                                                          |
| Set Global Address List visibility          | Hides the mailbox from the Global Address List, or shows it again.                                                                                                                                                                                                                                                        |
| Start Managed Folder Assistant              | Runs the assistant against the mailbox so retention settings and archiving are applied without waiting for the next scheduled pass.                                                                                                                                                                                       |
| Delete Mailbox                              | Deletes the mailbox.                                                                                                                                                                                                                                                                                                      |
| Set Copy Sent Items for Delegated Mailboxes | Controls whether mail sent as, or on behalf of, this mailbox is also copied into its Sent Items. Greyed out for anything other than a user or shared mailbox.                                                                                                                                                             |
| Set Litigation Hold                         | Places the mailbox on litigation hold for a chosen number of days, or lifts an existing hold with the **Disable Litigation Hold** switch. Greyed out when the mailbox is not licensed for litigation hold.                                                                                                                |
| Set Retention Hold                          | Places the mailbox on retention hold, or lifts one with the **Disable Retention Hold** switch.                                                                                                                                                                                                                            |
| Set Mailbox Locale                          | Sets the mailbox language and regional format, for example `en-GB` or `da-DK`.                                                                                                                                                                                                                                            |
| Set Max Send/Receive Size                   | Sets the largest message the mailbox may send and receive, in MB.                                                                                                                                                                                                                                                         |
| Set Send Quota                              | Sets the size at which the mailbox is stopped from sending.                                                                                                                                                                                                                                                               |
| Set Send and Receive Quota                  | Sets the size at which the mailbox is stopped from sending and receiving.                                                                                                                                                                                                                                                 |
| Set Quota Warning Level                     | Sets the size at which the user is warned that the mailbox is filling up.                                                                                                                                                                                                                                                 |
| Set Calendar Processing                     | Configures how the resource handles booking requests, covering automatic processing and acceptance, conflict handling, meeting duration and booking window limits, what is stripped from the meeting item, and the response text sent back to organizers. Greyed out for anything other than a room or equipment mailbox. |

## Exchange Information

The card on the left summarizes the mailbox. Its header carries a refresh button, and a warning appears above the details when Microsoft has blocked the mailbox for spam.

| Field                    | Description                                                                                                                                                                                                          |
| ------------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Mailbox Type             | The Exchange recipient type, such as `UserMailbox` or `SharedMailbox`.                                                                                                                                               |
| Hidden from GAL          | Whether the mailbox is hidden from the Global Address List.                                                                                                                                                          |
| Blocked For Spam         | Whether Microsoft has blocked the mailbox from sending because of spam activity.                                                                                                                                     |
| Retention Policy         | The retention policy applied to the mailbox.                                                                                                                                                                         |
| Mailbox Usage            | How much of the send and receive quota is in use, shown as a bar with the size used and the quota.                                                                                                                   |
| Forwarding Status        | Whether forwarding is off, or set to an internal or external address.                                                                                                                                                |
| Keep Copy in Mailbox     | Whether forwarded mail is also delivered to this mailbox. Shown only when forwarding is configured.                                                                                                                  |
| Forwarding Address       | The address mail is forwarded to. Shown only when forwarding is configured.                                                                                                                                          |
| Archive Mailbox Enabled  | Whether the archive mailbox exists.                                                                                                                                                                                  |
| Auto Expanding Archive   | Whether the archive can grow past its initial quota. The label reads **Auto Expanding Archive: (org)** when the setting comes from the organization rather than the mailbox. Shown only when the archive is enabled. |
| Total Archive Item Size  | The size of the archive in GB. Shown only when the archive is enabled.                                                                                                                                               |
| Total Archive Item Count | The number of items in the archive. Shown only when the archive is enabled.                                                                                                                                          |
| Mailbox Holds            | Which holds apply to the mailbox: compliance tag, retention, litigation, in-place, eDiscovery and Purview retention holds, and whether the mailbox is excluded from an organization-wide hold.                       |
| Mailbox Protocols        | Which access protocols are enabled: EWS, MAPI, OWA, IMAP, POP, ActiveSync and SMTP client authentication.                                                                                                            |

{% hint style="info" %}
The SMTP entry spells out its state rather than relying on the chip color, because the underlying property records whether SMTP client authentication is _disabled_. A green **SMTP Disabled** chip is the secure outcome, **SMTP Enabled** is the one worth acting on, and **SMTP Unknown** means Exchange did not report the setting.
{% endhint %}

## Proxy Addresses

Every address on the mailbox, listed with its type and whether it comes from Entra ID, Exchange or both. **Add Alias** opens a dialog where an address is built from a prefix and one of the tenant's domains, and several can be queued before submitting. Row actions promote an address to primary, or remove it.

{% hint style="info" %}
When an address appears in only one of Entra ID or Exchange, the card says so. This is usually a recent change that Microsoft is still propagating rather than a fault, so it is worth refreshing before acting on it.
{% endhint %}

## Mailbox Permissions

Who else can get into this mailbox, listed by user or group, access rights and the type of principal. **Add Permissions** opens a dialog offering Full Access, with an automapping switch so Outlook adds the mailbox on its own, along with Send As and Send on Behalf. A toggle in the dialog widens the picker to include mail-enabled security groups. The row action removes a permission.

## Mailbox Access

The other mailboxes this user can get into, listed with the mailbox name, its address and the rights held. The row action removes the user's access to the selected mailbox.

{% hint style="info" %}
This card is built from the cached mailbox permission report rather than a live Exchange query, which is what makes it fast enough to show a whole tenant's delegations. It only reflects what was true at the last cache sync, and reports an error asking you to sync the cache when no report data exists yet.
{% endhint %}

## Calendar Permissions

Who has access to this mailbox's calendar folders, listed by user or group, access rights, folder name and principal type. **Add Permissions** opens a dialog offering the full set of Exchange folder levels: Owner, Publishing Editor, Editor, Publishing Author, Author, Non Editing Author, Reviewer, Contributor, Limited Details, Availability Only and None. A **Delegate with Private item access** switch is available with Editor, which turns the grant into delegate access and lets the delegate see items marked private. The row action removes a permission.

## Contact Permissions

The same arrangement applied to the mailbox's contact folders, with the same permission levels and the same row action.

## Current Mailbox Rules

The inbox rules on the mailbox, listed with whether each is enabled, its name, description and priority. Row actions enable, disable or delete a rule.

{% hint style="info" %}
This card is worth a look during a compromise investigation, since rules that move or forward mail are a common way for an intruder to hide their activity. The bec.md tab gathers this alongside the other indicators.
{% endhint %}

## Trusted and Blocked Senders/Domains

The user's own safe and blocked sender lists, listed by type and value. The row action removes an entry.

## Mailbox Forwarding

Sets where the mailbox's mail goes.

| Field                                                   | Description                                                                                                                                |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Forward to Internal Address                             | Forwards to another recipient in the tenant, chosen from users and contacts.                                                               |
| Forward to External Address                             | Forwards to an address outside the tenant. The tenant's remote domain settings have to allow automatic forwarding for this to take effect. |
| Disable Email Forwarding                                | Clears the forwarding configuration.                                                                                                       |
| Keep a Copy of the Forwarded Mail in the Source Mailbox | Delivers the message to this mailbox as well as forwarding it. Without this, forwarded mail leaves no copy behind.                         |

## Out Of Office

Sets the mailbox's automatic replies.

| Field                                                    | Description                                                                                                                        |
| -------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| Auto Reply State                                         | Enabled, Disabled, or Scheduled for a fixed period.                                                                                |
| Start Date/Time, End Date/Time                           | The period replies are sent for. Only used when the state is Scheduled.                                                            |
| Internal Message                                         | The reply sent to people inside the organization.                                                                                  |
| External Message                                         | The reply sent to people outside the organization.                                                                                 |
| Block my calendar for this period                        | Creates a calendar event covering the absence, with a subject of your choosing. Only offered for a scheduled reply.                |
| Automatically decline new invitations during this period | Declines invitations that arrive for the absence. Only offered for a scheduled reply.                                              |
| Decline and cancel my meetings during this period        | Declines and cancels meetings already in the calendar, with an optional message to organizers. Only offered for a scheduled reply. |

## Recipient Limits

Sets the largest number of recipients the mailbox may address in a single message, which is a practical brake on a compromised account being used to send in bulk.

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
