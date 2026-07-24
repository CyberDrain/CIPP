# CIPP Backup

{% hint style="info" %}
This page is accessed from the General settings tab.
{% endhint %}

## Information Bar

The top bar will display statistical information about your CIPP backups including the number of backups run, the relative time since the last backup, the status of automatic backups, and when the next backup is scheduled.

## Action Buttons

<details>

<summary>Run Backup</summary>

Triggers a backup to run

</details>

<details>

<summary>Restore From File</summary>

Allows you to upload a previous CIPP backup to restore those settings

</details>

<details>

<summary>Enable Backup Schedule/Remove Schedule</summary>

Enables automatic backups or removes the scheduled backup. The option on this button will vary based on if a schedule is already present or not.

</details>

## Table Details

The table will display a list of previous backups.

{% hint style="info" %}
Backups are stored indefinitely. The low cost of Azure Table storage allows this to have minimal to no impact on self-hosted costs.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Restore Backup</td><td>Restores CIPP using the selected backup</td><td>false</td></tr><tr><td>Download Backup</td><td>Downloads the selected backup(s)</td><td>true</td></tr></tbody></table>

## What Gets Backed Up

The following tables will get copied into the backup:

* AccessRoleGroups
* ApiClients
* AppPermissions
* CommunityRepos
* Config
* CustomData
* CustomPowershellScripts
* CustomRoles
* CustomVariables
* Domains
* ExcludedLicenses
* Extensions - This table does not include the authentication for the extensions. You will need to manually set up the extensions again if you restore from a backup.
* GDAPRoles
* GDAPRoleTemplates
* GraphPresets
* ScheduledTasks
* SchedulerConfig
* Standards
* templates
* TenantProperties
* WebhookRules

## Backup Replication

This section allows you to replicate your backups to an external source.

{% hint style="info" %}
When enabled, each new backup is also uploaded to the external container described by the SAS URL. The SAS URL is stored securely in Key Vault. This does not copy existing backups. This will continue to push backups to the container without any consideration for storage costs, so please monitor your external storage usage.
{% endhint %}

Toggle on the category you wish to back up, paste in your container SAS URL, and click save. The SAS URL must have write and create permissions.

***

{% include "../../../../.gitbook/includes/feature-request.md" %}
