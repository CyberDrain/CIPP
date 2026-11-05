# Run History

Run History lists every run of your scripted alerts, one row per run per tenant, newest first. A run that found nothing still gets a row, so you can confirm an alert actually ran for a tenant rather than inferring it from a quiet inbox. Audit log alerts fire as log entries arrive rather than on a schedule, so they do not appear here.

Runs are kept for 30 days.

## Filters

The page opens on the last 24 hours of runs for every alert. Opened from **View Run History** on the [Alert Configuration](README.md) list, it shows one alert only, covering its full 30 days.

Expand **Filter Options** above the table to change what is shown, then select **Apply Filter**.

| Field   | Description                                                                                                          |
| ------- | -------------------------------------------------------------------------------------------------------------------- |
| Days    | How many days of runs to show, from 1 to 30. Values outside that range are brought back inside it.                   |
| Outcome | Show only runs with the selected outcomes. Choose any of `Completed`, `Skipped`, `Failed` and `Not reported`. Leave it empty to include all outcomes. |

## Table Details

| Column         | Description                                                                                                                                                                                    |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Executed Time  | When the run started.                                                                                                                                                                          |
| Scheduled Time | The run slot the alert was scheduled for. This can be earlier than **Executed Time** when the run was picked up late.                                                                         |
| Task Name      | The name of the alert.                                                                                                                                                                         |
| Outcome        | How the run ended. See [Outcomes](#outcomes).                                                                                                                                                  |
| Summary        | A one-line description of the run. For a completed run, the number of items that were new, reopened, continuing, resolved and snoozed. For a failed run, the error. For a skipped run, why it was skipped. |
| New            | Items reported for the first time on this run.                                                                                                                                                 |
| Reopened       | Items that had resolved earlier and were reported again on this run.                                                                                                                           |
| Resolved       | Items that were open before and were not reported on this run.                                                                                                                                 |
| Duration Ms    | How long the run took, in milliseconds.                                                                                                                                                        |

How items move between open, resolved and reopened is covered on [history.md](history.md "mention").

### Outcomes

| Outcome      | Meaning                                                                                                                                                                                         |
| ------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Completed    | The check ran to the end for the tenant and reported its results.                                                                                                                              |
| Skipped      | The run was held back because the alert already completed for the tenant within its minimum run interval. The summary names the interval and the last completed run. See [alert.md](alert.md "mention"). |
| Failed       | The check stopped with an error. The summary shows the error.                                                                                                                                   |
| Not reported | The check finished without reporting a result, so it may not have completed. Check the logbook for the tenant.                                                                                 |

{% include "../../../../../.gitbook/includes/feature-request.md" %}
