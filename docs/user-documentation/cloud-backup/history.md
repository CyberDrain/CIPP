# Restore History

Restore History lists the restores, restore previews and exports of the last 30 days, newest first.

## Table Details

| Column | Description |
| --- | --- |
| Requested | When the job was started. |
| Job | **Restore**, **Restore preview** or **Export**. |
| Status | **Queued**, **Running**, **Completed** or **Failed**. |
| Service | Exchange Online, OneDrive, SharePoint or Teams. |
| Backup Of | The mailbox, OneDrive, site or team the items came from. |
| Restored To | Where the items were restored. Exports show **Download**. |
| Requested By | The CIPP user who started the job. |
| Completed At | When the job finished. |
| Result | How many items were restored, skipped or failed, or how many were exported. |

Use the **Restores**, **Exports** and **Failed** filters to narrow the list.

Open a job to see its options, the result for each item and, for a job that failed, the reason. A job that is still running updates by itself. A saved preview can't be restored from here: run a new preview from [Browse & Restore](restore.md).

For an export, **Download export** saves the `.zip` file until it expires 7 days after it was created. Downloading needs the Cloud Backup restore permission.

{% include "../../../.gitbook/includes/feature-request.md" %}
