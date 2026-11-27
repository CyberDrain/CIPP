---
description: Onboard a new user, or bring back an existing account and undo what offboarding left behind
---

# Onboarding Wizard

The Onboarding Wizard creates a new user or brings an existing account back into use. For an existing account, such as a returning employee, it scans for settings left over from offboarding and lets you choose which to undo. This page lists the onboarding jobs already submitted, and **Start Onboarding** opens the wizard. **Re-onboard user** on the Users table opens it with that user already selected.

## Using the wizard

{% stepper %}
{% step %}
### Tenant Selection

The tenant the user belongs to. One tenant at a time, defaulting to the tenant selected in the top menu.
{% endstep %}

{% step %}
### Onboarding Type

**New user** or **Existing user**. The steps that follow depend on this choice.
{% endstep %}

{% step %}
### User Details (new users)

The same form as **Add User** on the Users page, with the same licence, group, alias and template options, followed by the **Mailbox and OneDrive setup** options below. Submitting creates the user and finishes the wizard.
{% endstep %}

{% step %}
### Scan and Review (existing users)

Select one user and CIPP scans the account. Each finding is listed with the fix that undoes it, and you tick the fixes to run.
{% endstep %}

{% step %}
### Re-entitle (existing users)

Choose the licences and groups the user gets back, any **Mailbox and OneDrive setup** options, and whether to run now or on a scheduled date.
{% endstep %}

{% step %}
### Confirmation

A summary of everything selected. Submitting creates the onboarding job. When the job runs immediately, the wizard stays open and shows each step's progress live.
{% endstep %}
{% endstepper %}

{% hint style="info" %}
The new user form loads licences and groups for the tenant selected in the top menu. If the wizard's tenant is different, switch the top menu to that tenant first.
{% endhint %}

## Scan and Review

Findings are grouped into four cards. A finding marked **Report only** is for information and has no fix. A finding marked **Next step** is handled on the Re-entitle step.

| Group            | What is checked                                                                                                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Account          | Sign-in is blocked. Password reset and Temporary Access Pass are always offered. Reported only: no MFA methods registered, and a missing immutable ID on a tenant that syncs from Active Directory. |
| Mailbox          | Converted to a shared mailbox, hidden from the Global Address List, forwarding still set, out of office still on. Reported only: inbox rules, a shared mailbox over 50 GB with no licence, and no mailbox at all. |
| Delegated access | Other people who still hold Full Access, Send As or Send on Behalf on the mailbox, who have access to the calendar, or who are site admins on the OneDrive. Each person is listed separately.      |
| Entitlements     | No licences or no group memberships (handled on the next step). Reported only: admin roles the user held before offboarding, and no devices.                                                       |

Fixes that are usually wanted start ticked. Untick anything that should stay as it is, such as a delegate who still needs access. For a user synced from Active Directory, enabling sign-in and resetting the password start unticked: do those in Active Directory. **Rescan** runs the checks again.

{% hint style="info" %}
Turn on **Show deleted users** to pick an account from deleted users. A deleted account has to be restored before it can be scanned, so the only action offered is **Restore and rescan**.
{% endhint %}

{% hint style="warning" %}
Admin roles are never restored by the wizard. If the user needs a role again, assign it from the Roles page.
{% endhint %}

If a check could not be completed, a warning names it. Its findings are missing from the scan, so do not read that group as clean.

## Re-entitle

| Option                                    | Description                                                                                                                                                                         |
| ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Restore from the offboarding snapshot     | Offered when CIPP offboarded the user and saved what they held. Tick the licences, the manager and the groups to give back. Each licence shows how many are unassigned in the tenant. |
| Use a template or copy from another user  | Choose a user template, licences, groups, or another user to copy group memberships from.                                                                                           |

Groups that cannot be restored are listed with the reason: dynamic groups follow their membership rule, groups synced from Active Directory are managed on-premises, and deleted groups no longer exist.

A group that grants admin roles to its members is only added when you have permission to manage privileged users. Without it, that group is skipped and reported on the job, and the rest are still added. The same permission is needed to enable sign-in, reset the password or issue a Temporary Access Pass for a user who holds an admin role.

{% hint style="info" %}
The snapshot is saved when the Offboarding Wizard removes a user's groups, licences or admin roles. Users offboarded before this feature was available, or outside CIPP, have no snapshot. Snapshots are kept for one year.
{% endhint %}

## Mailbox and OneDrive setup

Offered for new and existing users. Leave an option empty to skip it.

| Option                                    | Description                                                                                                              |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------ |
| Pre-provision OneDrive                    | Creates the user's OneDrive so it is ready before they first sign in.                                                    |
| Add OneDrive shortcuts to SharePoint sites | Adds a shortcut in the user's OneDrive to each site chosen. A site or document library URL can also be typed in. Choosing a shortcut always pre-provisions the OneDrive first. A OneDrive that is not ready yet gets the shortcut 30 minutes later, as its own job.         |
| Mailbox language                          | Sets the mailbox language and renames the default folders to match.                                                      |
| Time zone                                 | Sets the mailbox time zone. Available once a mailbox language is chosen.                                                  |
| Enable online archive                     | Turns on the archive mailbox.                                                                                            |
| Grant Full Access, Send As, Send on Behalf | Gives the selected people that access to the user's mailbox, with or without Outlook adding the mailbox automatically.   |
| Give access to the calendar               | Gives the selected people the chosen permission level on the user's calendar.                                            |

{% hint style="info" %}
For a new user these options run about 15 minutes after the user is created, because the mailbox and OneDrive do not exist straight away. When the creation is scheduled, they run 15 minutes after the scheduled date. The setup appears as its own job in the table on this page, and a step that fails, for example because the mailbox was not ready yet, can be run again from there.
{% endhint %}

## Scheduling & Notifications

| Setting                    | Description                                                                                                               |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| Schedule this onboarding   | Defers the job to a chosen date instead of running it immediately.                                                        |
| Webhook, E-mail, PSA       | Which channels are notified when the job completes. Each has to be configured in CIPP's notification settings to deliver. |
| Push notification to my devices | Sends a push notification to the browsers and installed apps you registered under [user-settings.md](../../shared-features/menu-bar/user-settings.md "mention"). |
| Reference                  | Free text added to the notification so the job can be recognised later.                                                   |

## Progress

Every job reports its progress as it runs, one line per fix. Opening a job from the table shows the same view. **Re-run** queues the whole job again, and the arrow next to a single step runs just that step again. A step that reports an error is shown as failed, and the steps after it still run.

The results of a password reset or a Temporary Access Pass are shown on their step.

## Table Details

| Column                | Description                                               |
| --------------------- | --------------------------------------------------------- |
| Tenant                | The tenant the job runs against.                          |
| Parameters - Username | The user being onboarded.                                 |
| Task State            | Whether the job is planned, running, completed or failed. |
| Scheduled Time        | When the job is due to run.                               |
| Executed Time         | When the job actually ran. Empty for a job still waiting. |

The table lists onboarding jobs for existing users, and the mailbox and OneDrive setup job of each new user that had setup options chosen. A new user created without any setup options only appears on the Users page.

{% include "../../../../.gitbook/includes/feature-request.md" %}
