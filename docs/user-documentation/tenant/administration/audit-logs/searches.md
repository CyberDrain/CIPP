# Log Searches

CIPP collects audit logs by planning a series of 60-minute search windows per tenant, then working each one through to completion: creating the search in Graph, polling it, downloading the records and processing them against your alert rules. This page is the ledger of those windows, so you can confirm coverage is unbroken and spot any window that failed. It is the everyday view; the advanced Search Coverage tab carries the full diagnostic detail.

## Search Options

The Search Options panel controls how far back the ledger is shown, filtered on each window's start time. It defaults to the last 48 hours.

| Field            | Description                                                                                                |
| ---------------- | ---------------------------------------------------------------------------------------------------------- |
| Date Filter Type | Choose `Relative` to look back a set amount of time from now, or `Start / End` to specify an exact window. |
| Last             | Shown for a relative filter. The number of hours or days to look back.                                     |
| Interval         | Shown for a relative filter. Whether the number above counts Hours or Days.                                |
| Start Date       | Shown for a start and end filter. The beginning of the range.                                              |
| End Date         | Shown for a start and end filter. The end of the range.                                                    |

Select **Apply Filters** to reload the ledger for the chosen range.

## Search Health

Beneath the Search Options panel, a row of chips summarizes the windows currently in view:

* **All log searches healthy** - No window in the range has failed permanently. Replaced by a count of windows that failed permanently when any have.
* **Currently searching** - How many windows are still in progress, meaning they are planned or created but not yet downloaded.
* **Skipped (auditing off)** - How many windows were skipped because unified auditing is not enabled for the tenant. Only shown when there are any.

{% hint style="warning" %}
Skipped windows mean no audit data was collected for that period, and it cannot be recovered later. If a tenant is showing skipped windows, enable unified auditing on that tenant before the gap grows.
{% endhint %}

## Table Details

| Column        | Description                                                                                                                                                                                 |
| ------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant        | The tenant the search window belongs to, shown as its default domain name.                                                                                                                  |
| Type          | The kind of ledger entry: `Window` for a normal planned 60-minute search window, `Reconciliation` for a gap-fill block, or `Manual` for a manually queued search bridged into the pipeline. |
| Window Start  | Start of the search window, in UTC.                                                                                                                                                         |
| Window End    | End of the search window, in UTC.                                                                                                                                                           |
| State         | Where the window sits in the pipeline: `Planned`, `Created`, `Downloaded`, `Retry`, `DeadLetter` (failed permanently) or `Skipped` (unified auditing off for the tenant).                   |
| Search Status | The underlying Graph audit log search status, such as `notStarted`, `running` or `succeeded`, refreshed on each poll.                                                                       |
| Record Count  | Number of audit records the window's Graph search returned and downloaded.                                                                                                                  |
| Matched Count | Number of downloaded records that matched an alert rule during processing.                                                                                                                  |
| Last Error    | The most recent error recorded for the window. Blank when healthy.                                                                                                                          |

{% hint style="info" %}
The ledger honors the tenant selector at the top of CIPP. Choose All Tenants to review coverage across your whole estate at once.
{% endhint %}

To queue a search of your own rather than wait for the scheduled windows, use the Manual Searches tab.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
