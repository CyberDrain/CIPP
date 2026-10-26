# Configuration Backup

Configuration Backup takes a scheduled copy of a tenant's configuration and lets you restore it later. Backups run as a scheduled task, are stored in CIPP's own storage, and can be previewed, downloaded as JSON, or restored selectively.

The page reflects the tenant selected in CIPP. With a specific tenant selected you see that tenant's backups alongside any global backups. With All Tenants selected you see every tenant's backups, and a tenant selector appears above the history list to narrow it down.

## Current Configuration

This card shows whether a backup schedule exists, and its button changes accordingly.

**Add Backup Schedule** is shown when no schedule exists and opens the scheduling flyout described below.

**Remove Backup Schedule** is shown when a schedule already exists. Removing it stops future automatic backups. Backup files already taken are kept and remain available to restore.

{% hint style="info" %}
A schedule created against All Tenants covers every tenant. A tenant-specific schedule can exist alongside a global one and runs on its own schedule, so a tenant can be covered twice.
{% endhint %}

### Add Backup Schedule

Choose the tenant the schedule applies to, then switch on the components to include. Every component is switched on by default. **Create Schedule** saves the task.

Backups run daily from the time the schedule is created. There is no recurrence or start-time option in this flyout.

| Setting                          | Description                                                                                                                                       |
| -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant Selection                 | The tenant the schedule applies to, or All Tenants for every tenant.                                                                              |
| User List                        | Backs up the tenant's user accounts and their properties.                                                                                         |
| Groups                           | Backs up groups and their membership.                                                                                                             |
| Conditional Access Configuration | Backs up the tenant's Conditional Access policies.                                                                                                |
| Intune Configuration Policies    | Backs up device configuration profiles.                                                                                                           |
| Intune Compliance Policies       | Backs up device compliance policies.                                                                                                              |
| Intune Protection Policies       | Backs up app protection policies.                                                                                                                 |
| Anti-Spam Policies               | Backs up the tenant's anti-spam policies.                                                                                                         |
| Anti-Phishing Policies           | Backs up the tenant's anti-phishing policies.                                                                                                     |
| Teams Phone Number Assignments   | Backs up which user or resource account each Teams phone number is assigned to, with its number type, assignment category and emergency location. |
| Webhook Alerts Configuration     | Backs up the alert webhooks configured in CIPP for the tenant.                                                                                    |
| Scripted Alerts Configuration    | Backs up the scripted alerts configured in CIPP for the tenant.                                                                                   |
| Custom Variables                 | Backs up the tenant's custom variables. See [global-variables.md](../administration/tenants/global-variables.md "mention").                       |

## Backup Schedule Details

Shown once a schedule exists. Use the refresh button in the card header to fetch the current state of the task.

| Field         | Description                                                                        |
| ------------- | ---------------------------------------------------------------------------------- |
| Backup Name   | The name of the scheduled task, generated as CIPP Backup - followed by the tenant. |
| Tenant        | The tenant the schedule applies to.                                                |
| Recurrence    | How often the backup runs. Scheduled backups run daily.                            |
| Task State    | The state of the underlying scheduled task, for example Planned or Completed.      |
| Last Executed | How long ago the task last ran, or Never if it has not yet run.                    |
| Next Run      | When the task is next due, or Not scheduled where no run is queued.                |

## Backup Components

Lists the components included in the current schedule as a set of tags. Where a schedule exists but no components were selected, the card shows that no components are configured.

## Backup History

Each backup is shown as a card, most recent first. Use the refresh button to pull the latest backups from storage. With All Tenants selected, each card also shows which tenant the backup came from, and the tenant selector filters the list.

| Item              | Description                                                               |
| ----------------- | ------------------------------------------------------------------------- |
| Name              | The date and time the backup was taken, read from the backup's file name. |
| Time Since Backup | How long ago the backup was taken.                                        |
| Preview           | Opens a flyout showing the contents of the backup as structured JSON.     |
| Download          | Downloads the backup as a JSON file.                                      |
| Restore           | Opens the restore flyout for the selected backup.                         |

## Restore Configuration Backup

Restoring writes the selected components from a backup back into the tenant. The restore is queued as a task rather than run immediately, so the result appears once the task has executed.

| Setting                    | Description                                                                                                                                           |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Backups for \<tenant>      | The backup to restore from. Opening the flyout from a backup card pre-selects that backup.                                                            |
| Restore Settings           | The components to restore, matching the component list used when scheduling a backup. Switch off anything you do not want written back.               |
| Overwrite existing entries | Replaces existing objects with the versions held in the backup. Leave this off to skip anything that already exists and restore only what is missing. |
| Send Restore results to    | Where the outcome is reported once the restore has run: Webhook, E-mail, or PSA.                                                                      |

{% hint style="info" %}
Restoring Teams Phone Number Assignments re-assigns each backed-up number to the user or resource account that held it, which also re-enables Enterprise Voice on that account. The account must hold a Teams Phone licence before the restore runs. Restored assignments can take a minute to appear on the [business-voice.md](../../teams-share/teams/business-voice.md "mention") page. A number that is currently assigned to a different account is skipped unless Overwrite existing entries is on, in which case it is moved back.
{% endhint %}

{% hint style="warning" %}
Overwriting replaces current settings with those in the backup rather than merging them. Where users are included in the restore, every property on the account is overwritten with the backed-up values. To protect a component, switch it off in Restore Settings or leave Overwrite existing entries off.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
