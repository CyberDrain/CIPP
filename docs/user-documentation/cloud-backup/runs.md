# Runs

Every backup of one service in one tenant is recorded as a run. The table shows the newest runs first, and you can show the runs for a single policy with the filter above the table.

## Table Details

| Column | Description |
| --- | --- |
| Started At | When the backup started. |
| Policy Name | The policy that ran. |
| Tenant | The tenant that was backed up. |
| Service | Exchange Online, OneDrive, SharePoint or Teams. |
| Status | **Succeeded**, **Partial success** (some mailboxes, OneDrives, sites or teams failed or reported a warning), **Failed**, or **Running**. |
| Sources | How many mailboxes, OneDrives, sites, or teams and chat users the run covered. |
| Items | The number of messages, events, contacts, files and Teams messages added or changed. |
| Size | The size of what was uploaded to the destination. |
| Duration | How long the backup took. |

Open a run to see its details and a table with the result for each mailbox, OneDrive, site or team: items backed up, size, items removed because they were deleted in Microsoft 365, and any warnings. Items that couldn't be backed up are tried again in the next run.

Run history is kept for as long as the policy keeps its backups.

{% include "../../../.gitbook/includes/feature-request.md" %}
