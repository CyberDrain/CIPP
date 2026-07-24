# Log Searches

This page will show the results of any audit log searches completed by CIPP.

## Filter Search List

Use this expandable section to adjust the results displayed in the table below. Choose the Status and Date Range you would like to view.

## Action Buttons

| Action     | Description                                                                                                                          |
| ---------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| New Search | Opens a modal to allow you to create a new audit log search. Select the settings you desire on the search before clicking `Confirm`. |

## Table Details

| Column        | Description                                                                                                                                                                                                |
| ------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant        | The tenant the search window belongs to, shown as its default domain name (the ledger's partition key).                                                                                                    |
| Type          | The kind of ledger entry: `Window` (a normal planned 60-minute search window), `Reconciliation` (a `RECON-*` gap-fill block), or `Manual` (a `MANUAL-*` manually queued search bridged into the pipeline). |
| Window Start  | Start of the search window, in UTC.                                                                                                                                                                        |
| Window End    | End of the search window, in UTC.                                                                                                                                                                          |
| State         | Where the window sits in the V2 pipeline: `Planned`, `Created`, `Downloaded`, `Retry`, `DeadLetter` (failed permanently), or `Skipped` (unified auditing off for the tenant).                              |
| Search Status | The underlying Graph audit-log search status (e.g. `notStarted`, `running`, `succeeded`), refreshed on each poll.                                                                                          |
| Record Count  | Number of audit records the window's Graph search returned and downloaded.                                                                                                                                 |
| Matched Count | Number of downloaded records that matched during alert processing.                                                                                                                                         |
| Last Error    | The most recent error recorded for the window, if any (blank when healthy).                                                                                                                                |

***

{% include "../../../../../.gitbook/includes/feature-request.md" %}
