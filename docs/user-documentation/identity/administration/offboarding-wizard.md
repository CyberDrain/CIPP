---
description: Offboard the selected user with standard requirements
---

# Offboarding Wizard

The Offboarding Wizard applies a standard set of leaver actions to one or more users, either immediately or on a scheduled date. This page lists the offboarding jobs already submitted, and **Start Offboarding** opens the wizard.

## Using the wizard

{% stepper %}
{% step %}
### Tenant Selection

The tenant the users belong to. One tenant at a time, defaulting to the tenant selected in the top menu.
{% endstep %}

{% step %}
### User Selection

The users to offboard. Several can be selected, and every option chosen in the next step is applied to each of them.
{% endstep %}

{% step %}
### Offboarding Options

Three groups of settings, described below.
{% endstep %}

{% step %}
### Confirmation

A summary of everything selected. Submitting creates the offboarding job.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
The options are pre-filled from your saved offboarding defaults each time the tenant changes. A tenant with its own defaults takes precedence over your personal ones, and the wizard states which set it has applied at the top of the Offboarding Settings card. You can manage these defaults using [user-settings.md](../../shared-features/menu-bar/user-settings.md "mention").
{% endhint %}

## Offboarding Settings

| Setting                            | Description                                                                                                     |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Convert to Shared Mailbox          | Converts the user's mailbox to a shared mailbox, so it can be kept without a license.                           |
| Hide from Global Address List      | Hides the user from address lists.                                                                              |
| Cancel all calendar invites        | Cancels upcoming meetings the user organized.                                                                   |
| Remove user's mailbox permissions  | Removes the user's access to every other mailbox.                                                               |
| Remove user's calendar permissions | Removes the user's access to every other calendar.                                                              |
| Remove all Rules                   | Deletes the inbox rules on the user's mailbox.                                                                  |
| Remove all Mobile Devices          | Removes the mobile devices registered against the mailbox.                                                      |
| Remove from all groups             | Removes the user from every group they belong to.                                                               |
| Remove Licenses                    | Strips every license from the account.                                                                          |
| Revoke all sessions                | Invalidates the account's tokens so every device has to sign in again.                                          |
| Disable Sign in                    | Blocks the account from signing in.                                                                             |
| Clear Immutable ID                 | Clears the on-premises anchor. Only effective once the account is no longer synchronised from Active Directory. |
| Reset Password                     | Sets a new random password.                                                                                     |
| Remove all MFA Devices             | Removes every registered authentication method.                                                                 |
| Remove Teams Phone DID             | Releases the phone number assigned to the user in Teams.                                                        |
| Disable OneDrive Sharing Links     | Revokes the sharing links the user created in OneDrive.                                                         |
| Delete user                        | Deletes the account.                                                                                            |

{% hint style="warning" %}
Deleting the user removes the mailbox with it, so it cannot be combined with converting to a shared mailbox. Where the mailbox needs to be kept, convert it and leave the account in place.
{% endhint %}

{% hint style="warning" %}
Converting a mailbox that is at or near 50 GB may fail, and a converted mailbox over that size stops receiving mail once its license is removed unless an Exchange Online Plan 2 license is assigned. The wizard checks the size of the selected mailboxes and warns before you submit.
{% endhint %}

## Permissions and forwarding

| Setting                        | Description                                                                                                                                   |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Grant Full Access (no automap) | Gives the selected users full access to the mailbox without Outlook adding it automatically.                                                  |
| Grant Full Access (automap)    | Gives full access and lets Outlook add the mailbox on its own.                                                                                |
| Grant Onedrive Full Access     | Gives the selected users full access to the user's OneDrive.                                                                                  |
| Disable Email Forwarding       | Clears any forwarding already set on the mailbox. Turning this on empties the forwarding fields below, since the two work against each other. |
| Forward Email To               | The recipient the user's mail is forwarded to.                                                                                                |
| Keep a copy of forwarded mail  | Delivers the message to the offboarded mailbox as well as forwarding it.                                                                      |
| Out of Office Message          | The automatic reply set on the mailbox, composed in a rich text editor.                                                                       |

{% hint style="info" %}
When the account is being deleted, its OneDrive is retained for 30 days by default, so granting OneDrive access is still worth doing if the contents may be needed.
{% endhint %}

## Scheduling & Notifications

| Setting                    | Description                                                                                                               |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Schedule this offboarding  | Defers the job to a chosen date instead of running it immediately, and reveals the settings below.                        |
| Scheduled Offboarding Date | When the job should run.                                                                                                  |
| Webhook, E-mail, PSA       | Which channels are notified when the job completes. Each has to be configured in CIPP's notification settings to deliver. |
| Reference                  | Free text added to the notification so the job can be recognized later.                                                   |

{% hint style="info" %}
Selecting three or more users turns scheduling on by itself, since a large offboarding is better queued than run against every account at once. The date can still be set to whatever suits.
{% endhint %}

## Filters

| Filter    | Shows                            |
| --------- | -------------------------------- |
| Running   | Jobs currently executing.        |
| Planned   | Jobs scheduled but not yet run.  |
| Failed    | Jobs that did not complete.      |
| Completed | Jobs that have run successfully. |

## Table Details

| Column                | Description                                               |
| --------------------- | --------------------------------------------------------- |
| Tenant                | The tenant the job runs against.                          |
| Parameters - Username | The user being offboarded.                                |
| Task State            | Whether the job is planned, running, completed or failed. |
| Scheduled Time        | When the job is due to run.                               |
| Executed Time         | When the job actually ran. Empty for a job still waiting. |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Task Details</td><td>Opens the <a data-mention href="../../tools/scheduler/task.md">task.md</a> page for the selected job, showing its full parameters and results. Requires scheduler read permissions.</td><td>false</td></tr><tr><td>Run Now</td><td>Runs the selected job immediately rather than waiting for its scheduled date. Requires scheduler write permissions.</td><td>true</td></tr><tr><td>Delete Job</td><td>Removes the job so it never runs. Requires scheduler write permissions.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
