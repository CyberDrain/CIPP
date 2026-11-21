# Policies

A backup policy decides which tenants and services are backed up, how often, where the backups go and how long earlier versions are kept.

## Policy settings

| Setting | Description |
| --- | --- |
| Policy name | A name for the policy. |
| Enabled | Disabled policies keep their settings but don't run on schedule. |
| Destination | Where backups are stored. Add a [destination](destinations.md) first if there isn't one. The destination must have versioning turned on: the form warns you when its last connection test found versioning off, and the policy can't be saved until it is on. |
| Tenants | Pick individual tenants, tenant groups, or All Tenants. Groups and All Tenants include tenants added later. |
| What to back up | Turn on Exchange Online, OneDrive, SharePoint and Teams separately. All four are on for a new policy. |
| Schedule | How often each service is backed up. |
| Exclusions | Users, groups and sites to leave out. See [Exclusions](#exclusions). |
| Keep deleted and changed items for (days) | Between 7 and 3650 days. The default is 90. |
| Encrypt backups | Encrypts every item before it leaves CIPP. |

## Schedules

Each service has its own schedule:

| Service | Default | Choices |
| --- | --- | --- |
| Exchange Online | Every 4 hours | Every 4, 6 or 12 hours, or every day |
| Teams | Every 4 hours | Every 4, 6 or 12 hours, or every day |
| OneDrive | Every 6 hours | Every 6 or 12 hours, or every day |
| SharePoint | Every 6 hours | Every 6 or 12 hours, or every day |

**Run Backup Now** backs up every service of the policy straight away without changing the schedule.

## Exclusions

| Exclusion | Effect |
| --- | --- |
| Excluded users | The user's mailbox, OneDrive and chats are not backed up. Enter a user principal name or an object ID. |
| Excluded groups | Every member of the group is left out, including members of nested groups. Enter the group's object ID. |
| Excluded sites | The site is not backed up. Enter the full site address, for example `https://contoso.sharepoint.com/sites/archive`. |

When the policy covers a single tenant, you can pick users and groups from a list. For several tenants, type the values instead.

## Permissions

To read the content of each tenant, CIPP's own app needs Microsoft Graph application permissions in that tenant. When you save a policy, CIPP adds the permissions the chosen services need to every tenant of the policy:

| Service | Permissions |
| --- | --- |
| Exchange Online | Mailbox read, folder create, and import and export permissions |
| OneDrive and SharePoint | Files.ReadWrite.All and Sites.ReadWrite.All |
| Teams | Chat.Read.All, ChannelMessage.Read.All, Team.ReadBasic.All and Channel.ReadBasic.All |

The write permissions are what restore uses to put mail and files back.

CIPP adds the permissions through your GDAP relationship. Granting Microsoft Graph application permissions needs the **Privileged Role Administrator** role, which is one of CIPP's recommended GDAP roles. Without it the tenant shows **Failed**. The policy is saved even when a tenant fails. The policy's details list each tenant with **Granted**, **Pending** or **Failed** and the reason. Fix the cause, then use **Grant again** for that tenant or **Grant Permissions** for all of them.

### Revoking permissions

When a tenant is no longer in any policy, for example after you remove it from a policy, delete the policy or the tenant leaves a tenant group, the Policies page lists it under **Permissions No Policy Needs**. Use **Revoke Permissions** to take back the permissions cloud backup added there. Permissions CIPP already had in the tenant, and permissions CIPP needs for its other features, are kept. If you add the tenant to a policy again later, CIPP grants the permissions again when you save the policy.

## Retention

When you save a policy, CIPP adds a lifecycle rule to the destination for that policy's backups. The latest copy of every item is always kept. Earlier versions of changed items, and items deleted in Microsoft 365, are removed by the storage provider after the number of days you set, without CIPP having to be online. Other lifecycle rules on the storage account or bucket are left alone. Deleting a policy removes its rule, but backups already stored stay until you delete them.

## Encryption

With encryption on, every item is encrypted with a key that is kept in CIPP's Key Vault, not in the destination. Anyone with access to the storage alone can't read the backups.

{% hint style="warning" %}
If the keys in CIPP's Key Vault are lost, encrypted backups can't be read. Make sure the Key Vault is part of your own backup and recovery plan.
{% endhint %}

**Rotate Encryption Key** creates a new key for future backups. Previous keys are kept, so older backups stay readable.

## Table Actions

| Action | Description |
| --- | --- |
| Edit Policy | Changes the policy's settings. |
| Run Backup Now | Backs up every tenant and service in the policy straight away. The schedule is not changed. |
| Grant Permissions | Adds the permissions the policy needs to every tenant again. |
| View Runs | Opens the runs page filtered to this policy. |
| Rotate Encryption Key | Creates a new encryption key. Only shown when encryption is on. |
| Delete Policy | Stops the policy and removes its retention rule. Stored backups and encryption keys are kept. |

{% include "../../../.gitbook/includes/feature-request.md" %}
