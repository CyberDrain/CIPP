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

A summary of everything selected, which folds away once you submit. Submitting creates the offboarding job. When the job runs immediately, the wizard stays open and shows each user's progress live, one line per selected action, until every action has finished. Each user's block can be copied as text, **Re-run** queues that user's full set of actions again, and the arrow next to a single action runs just that one again.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
The options are pre-filled from your saved offboarding defaults each time the tenant changes. A tenant with its own defaults takes precedence over your personal ones (the whole tenant defaults blob wins, including an empty Out of Office message), and the wizard states which set it has applied at the top of the Offboarding Settings card. You can manage these defaults using [user-settings.md](../../shared-features/menu-bar/user-settings.md "mention"), or per tenant under Manage Tenant.
{% endhint %}

## Offboarding Settings

| Setting                            | Description                                                                                                     |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------- |
| Convert to Shared Mailbox          | Converts the user's mailbox to a shared mailbox, so it can be kept without a licence.                           |
| Hide from Global Address List      | Hides the user from address lists.                                                                              |
| Cancel all calendar invites        | Cancels upcoming meetings the user organised.                                                                   |
| Remove user's mailbox permissions  | Removes the user's access to every other mailbox.                                                               |
| Remove user's calendar permissions | Removes the user's access to every other calendar.                                                              |
| Remove all Rules                   | Deletes the inbox rules on the user's mailbox.                                                                  |
| Wipe Mobile Devices (account data only) | Wipes only the Exchange account data (mail, contacts, calendar) from each mobile device registered on the mailbox, without removing the device itself or its personal data. Delivered the next time the device connects to Exchange, and needs a modern ActiveSync client; an older device fails the wipe rather than falling back to a full device wipe. |
| Remove all Mobile Devices          | Removes the mobile devices registered against the mailbox.                                                      |
| Remove from all groups             | Removes the user from every group they belong to.                                                               |
| Remove group ownership             | Removes the user as owner of every group they own, including distribution lists. When this is on, a **New group owner** field appears: that person is added as owner of each of those groups first, and only then is the user removed. Without a new owner, a group the user is the only owner of cannot be released and is reported as failed. |
| Remove Licenses                    | Strips every licence from the account.                                                                          |
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
Converting a mailbox that is at or near 50 GB may fail, and a converted mailbox over that size stops receiving mail once its licence is removed unless an Exchange Online Plan 2 licence is assigned. An archive over 50 GB, or a litigation hold, also needs the mailbox to keep a licence. The wizard checks the selected mailboxes against the overnight mailbox data and warns before you submit.
{% endhint %}

{% hint style="info" %}
The account-only wipe is issued before sessions are revoked, sign-in is disabled or mobile devices are removed, whatever order those settings appear in above. The wipe depends on the account still being able to authenticate and the device's ActiveSync partnership still existing at the point it is issued.
{% endhint %}

## Permissions and forwarding

| Setting                        | Description                                                                                                                                   |
| ------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Grant Full Access (no automap) | Gives the selected users full access to the mailbox without Outlook adding it automatically.                                                  |
| Grant Full Access (automap)    | Gives full access and lets Outlook add the mailbox on its own.                                                                                |
| Grant Send As Access           | Lets the selected users send mail as the offboarded user, so it appears to come from them.                                                    |
| Grant Send on Behalf Access    | Lets the selected users send mail on the offboarded user's behalf, which recipients see as sent by them on behalf of the leaver.              |
| Grant OneDrive Full Access     | Gives the selected users full access to the user's OneDrive.                                                                                  |
| Disable Email Forwarding       | Clears any forwarding already set on the mailbox. Turning this on empties the forwarding fields below, since the two work against each other. |
| Forward Email To               | The recipient the user's mail is forwarded to.                                                                                                |
| Keep a copy of forwarded mail  | Delivers the message to the offboarded mailbox as well as forwarding it.                                                                      |
| Out of Office Message          | The automatic reply set on the mailbox, composed in a rich text editor. Leave blank to skip. Supports CIPP `%variable%` tokens such as `%tenantname%` and tenant custom variables; they stay literal in the form and are resolved when the job runs. `%username%` is a reserved Windows-style token and is **not** replaced with the offboarded user. |

{% hint style="info" %}
When the account is being deleted, its OneDrive is retained for 30 days by default, so granting OneDrive access is still worth doing if the contents may be needed.
{% endhint %}

{% hint style="info" %}
Selecting **Delete user** greys out the mailbox access, forwarding and out of office settings, since the mailbox goes with the account. OneDrive access stays available.
{% endhint %}

## Scheduling & Notifications

| Setting                    | Description                                                                                                               |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Schedule this offboarding  | Defers the job to a chosen date instead of running it immediately, and reveals the settings below.                        |
| Scheduled Offboarding Date | When the job should run.                                                                                                  |
| Webhook, E-mail, PSA       | Which channels are notified when the job completes. Each has to be configured in CIPP's notification settings to deliver. |
| Push notification to my devices | Sends a push notification to the browsers and installed apps you registered under [user-settings.md](../../shared-features/menu-bar/user-settings.md "mention"). Only you receive it. You need at least one device registered there first; without one, the offboarding is not queued and the results explain where to enrol. |
| HaloPSA Ticket             | An existing HaloPSA ticket to add the results to as a note, instead of raising a new ticket. Only shown once PSA is selected and the HaloPSA integration is enabled. |
| Reference                  | Free text added to the notification so the job can be recognised later.                                                   |

{% hint style="info" %}
Selecting three or more users turns scheduling on by itself, since a large offboarding is better queued than run against every account at once. The date can still be set to whatever suits.
{% endhint %}

## Progress

Every job reports its progress as it runs. Opening a job from the table, or choosing **View Task Details**, shows a **Progress** section that lists each selected action with its current state and outcome, refreshing on its own until the job finishes. It is the same view the wizard shows for a job that runs immediately.

An action that reports an error line, such as a group the user could not be removed from, is shown as failed even when its other items succeeded, and the user's overall result follows the same rule. Each user's block has a copy button that places the block on the clipboard as text.

Notification channels chosen for the job (webhook, e-mail, PSA, push) are the last steps of the user's block from the start. They run once every action has finished and show whether each delivery succeeded, and the outcomes are recorded on the task as well.

**Re-run** queues that user's full set of actions again, the same as **Run Now** on the task. The arrow next to a single action runs only that action again: it is queued as its own job, named after the action, so it has results and logs of its own, and it reports into the same progress block. Both use the wizard's own permission, and actions that are not repeatable without effect, such as a password reset, happen again.

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
