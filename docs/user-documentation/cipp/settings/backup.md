# CIPP Backup

CIPP backups capture the configuration of your CIPP instance itself, covering standards, templates, scheduled tasks, roles, and integration settings. Backups are held in the storage account belonging to your CIPP instance, can be downloaded as JSON, and can be restored selectively. Automatic daily backups run through the scheduler once enabled.

{% hint style="warning" %}
Backups do not include authentication material. The SAM application credentials and the API keys for your integrations are not captured, so a restored instance still needs those entered again by hand.
{% endhint %}

## Information Bar

The bar across the top summarizes the current backup position.

| Item              | Description                                                                       |
| ----------------- | --------------------------------------------------------------------------------- |
| Backup Count      | How many backups are currently held.                                              |
| Last Backup       | How long ago the most recent backup ran, or a note that none exist yet.           |
| Automatic Backups | Whether the daily backup schedule is in place.                                    |
| Next Backup       | When the next scheduled backup is due, or Not Scheduled where no schedule exists. |

## Page Actions

| Button            | Description                                                                                             |
| ----------------- | ------------------------------------------------------------------------------------------------------- |
| Run Backup        | Takes a backup immediately, after a confirmation prompt.                                                |
| Restore From File | Opens a file picker for a previously downloaded JSON backup, then starts the restore wizard against it. |
| Schedule Backups  | Creates the daily automatic backup schedule. Shown only when no schedule exists.                        |
| Remove Schedule   | Deletes the daily automatic backup schedule. Shown only when a schedule is already in place.            |

## Table Details

| Column      | Description                                                                    |
| ----------- | ------------------------------------------------------------------------------ |
| Backup Name | The identifier of the backup, which also becomes the filename when downloaded. |
| Timestamp   | When the backup was taken.                                                     |

{% hint style="info" %}
Backups are removed automatically once they exceed the retention period set under **Backup Retention** on the General settings tab. The default is 30 days, the minimum is 7, and the cleanup job runs daily at 2:00 AM. Download anything you want to keep beyond that window.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Restore Backup</td><td>Loads the selected backup and opens the restore wizard.</td><td>false</td></tr><tr><td>Download Backup</td><td>Downloads the selected backup as a JSON file.</td><td>true</td></tr></tbody></table>

{% hint style="info" %}
Downloads are validated on the way out. Where a backup has minor structural problems that CIPP can correct, the corrected version is downloaded instead and `_repaired` is appended to the filename.
{% endhint %}

## Restoring a Backup

Both **Restore From File** and the **Restore Backup** row action open the same three-step wizard, so a restore is never applied straight from a click.

{% stepper %}
{% step %}
### Validation

The backup is checked before anything else happens. A passing backup reports how many valid rows it holds and across how many categories, along with any warnings and a note where minor issues were repaired automatically.

A backup that fails validation cannot be taken any further, and the errors are listed so you can see why.
{% endstep %}

{% step %}
### Select Categories

Choose which parts of the backup to restore. Categories are listed with the number of items each contains, and each can be expanded to preview the individual items before deciding.

This is what makes a partial restore possible, for example recovering only your standards or only your scheduled tasks without disturbing anything else.
{% endstep %}

{% step %}
### Confirm and Restore

Review the selected categories and item counts, then select **Restore**.
{% endstep %}
{% endstepper %}

{% hint style="danger" %}
Restoring overwrites your current configuration for every category you selected, and cannot be undone. Take a fresh backup first if the current state is worth keeping.
{% endhint %}

## What Gets Backed Up

The following configuration is captured.

| Area                    | Contents                                                                                                                                 |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Access and permissions  | App permissions, access role groups, API clients, custom roles                                                                           |
| Tenants                 | Tenant properties, tenant groups and their members, and the exclusion state of any excluded tenants                                      |
| Standards and templates | Standards, and all template types including Conditional Access, Intune, group, contact, Exchange connector and the rest                  |
| Automation              | Scheduled tasks, scheduler configuration, webhook rules, custom PowerShell and test scripts                                              |
| Reference data          | Domains, excluded licenses, Graph Explorer presets, GDAP roles and role templates, community repositories, custom data, custom variables |
| Configuration           | The CIPP configuration table, including extension settings                                                                               |

{% hint style="warning" %}
Extension settings are backed up, but the credentials behind them are not. After a restore you will need to re-enter the API keys and secrets for every integration before they will work again.
{% endhint %}

A few areas are captured selectively rather than in full. Scheduled tasks exclude anything already completed, so a restore does not resurrect finished jobs. Tenants capture only the rows for tenants you have excluded, rather than the whole tenant list, which CIPP rebuilds itself.

## Backup Replication

Replication uploads each new backup to an external Azure Storage container, so that a copy exists outside the storage account your CIPP instance depends on. Two scopes can be configured independently.

| Scope             | Description                                                |
| ----------------- | ---------------------------------------------------------- |
| CIPP Core Backups | Replicates the CIPP configuration backups described above. |
| Tenant Backups    | Replicates all scheduled tenant backups.                   |

Each scope has the same two settings.

| Setting            | Description                                                                                                                                                                  |
| ------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Enable replication | Turns replication on for that scope.                                                                                                                                         |
| Container SAS URL  | A container-level SAS URL with write and create permissions. Stored securely in the key vault and masked once saved. Leave blank on a later save to keep the existing value. |

{% hint style="warning" %}
Replication applies to new backups only. Existing backups are not copied across when you enable it, and CIPP does not manage or prune what it writes to the external container, so keep an eye on the storage costs there yourself.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
