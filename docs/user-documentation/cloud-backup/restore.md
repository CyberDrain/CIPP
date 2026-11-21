# Browse & Restore

Browse & Restore shows what a policy has backed up, as it was at any backup in the retention period. From here you can download single items, restore mail and files to Microsoft 365, and export whole folders or mailboxes as a `.zip` file.

## Choose a backup

| Setting | Description |
| --- | --- |
| Policy | The backup policy. |
| Tenant | A tenant the policy backs up. |
| Service | Exchange Online, OneDrive, SharePoint or Teams. |
| Backed up mailbox, OneDrive, site or team | Everything the policy has backed up for this tenant and service. Mailboxes, OneDrives and sites that are no longer in the tenant are still listed, marked **removed from the tenant**. Ones the policy now excludes are marked **excluded from the policy**. |
| Point in time | Each completed backup. The newest is selected. Pick an earlier one to see items as they were then, including items deleted or changed since. |

## Browsing and searching

The folder path above the list shows where you are. Click a folder to open it, and use **All folders** or a folder in the path to go back up.

**Search this backup** finds items anywhere in the mailbox, OneDrive, site or team by subject, sender, file name or folder. Use **Type** to show only one kind of item, such as email, calendar events, contacts or files. **Modified from** and **Modified to** limit the list to items changed between two dates. With a folder open, turn on **Only search the open folder** to search just that folder and its subfolders. Large folders are shown 100 items at a time: use **Next** and **Previous** to move through them.

Click an item to see its details and its earlier versions. **Download** saves the item as it was at the chosen point in time: emails as `.eml` files, files as they were stored, and other items as JSON. **Download This Version** on an earlier version saves that version.

## Restoring

Select items in the table, or tick folders in the folder list, then click **Restore**. With nothing selected, everything in the folder you have open is restored, or the whole mailbox, OneDrive or site when no folder is open.

| Option | Description |
| --- | --- |
| Restore to | The original mailbox, OneDrive or site, or another user in the same tenant. Mail is restored to the other user's mailbox, and OneDrive and SharePoint files to the other user's OneDrive. Restoring to another tenant isn't possible. |
| Restore into | **A new folder named "Restored" with the date and time** (the default) keeps the original folder structure inside that folder. **The original folders** puts items back where they were, creating folders that no longer exist. Files restored to another user always go into a new "Restored" folder at the top of their OneDrive. |
| When an item already exists | **Skip** (the default) leaves the existing item alone. **Overwrite** replaces it with the backed up version. **Keep both** restores a copy with "(restored" and the date added to its name. |

Every restore starts with **Preview restore**. The preview checks the backup against what is in Microsoft 365 now and lists what would happen to each item, without changing anything. When it is done, check the list, then click **Restore N items** and confirm. The restore uses exactly the options and items that were previewed: if you change anything after the preview, preview again. A preview can be used for one restore, within an hour.

The restore runs in the background. The page shows its progress and the result for each item, and the result is also kept in [Restore History](history.md).

Teams chats and channel messages can't be restored into Teams. Export them instead.

### Mailboxes, OneDrives and sites that left the tenant

When a user or site is removed from the tenant, or the policy starts excluding it, its backups are kept and stay available here. They are deleted once the policy's retention period has passed. Because the original no longer exists, it can only be restored to another user.

## Exporting

Select items or folders as for a restore and click **Export**. CIPP builds a `.zip` file in the background with:

* emails as `.eml` files, and calendar events and contacts as JSON
* files as they were stored, in their folders
* Teams conversations as a readable HTML page, plus the original messages as JSON

When the export is ready, click **Download export**. Exports can be downloaded for 7 days from this page or from [Restore History](history.md), and are then deleted. Items that couldn't be exported are listed in `_export-report.txt` inside the file. When the policy encrypts its backups, the export is stored encrypted as well; CIPP decrypts it while you download it.

## Permissions

Browsing and searching need the Cloud Backup read permission. Restoring, exporting and downloading need the Cloud Backup restore permission (`CIPP.CloudBackupRestore.ReadWrite`). The built-in admin and superadmin roles have it, the editor and readonly roles don't. Every restore, export and download is recorded in the logbook.

{% include "../../../.gitbook/includes/feature-request.md" %}
