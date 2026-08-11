# Logbook

The Logbook records every action CIPP performs, whether triggered by a technician, a scheduled task, an alert, or a background process. It is the primary tool for monitoring and troubleshooting, letting you confirm that an operation ran, see why one failed, and trace what CIPP was doing at a given moment.

By default the table shows entries for the current day only. Results are also scoped to the tenant currently selected in CIPP, and to the tenants your role gives you access to. Entries CIPP records against itself rather than a customer are always included.

## Using the Logbook for Troubleshooting

You can verify whether a specific action occurred by checking the log entries. For example, to confirm that the scheduled task "Hudu Extension Sync" ran successfully, select the appropriate date, filter or search for `Hudu Extension Sync`, and review the entries returned.

{% hint style="warning" %}
If an expected action is not logged, it might indicate a failure that occurred before the data was collected. If an alert is expected but not present in the logbook, it could indicate a failure in the data collection process. Such issues typically require developer intervention for identification and resolution. If you are a sponsor, please reach out to the helpdesk in these cases.
{% endhint %}

## Logbook Filters

Expanding the **Logbook Filters** section at the top of the page reveals the options for narrowing what is retrieved. The section header shows the date currently in effect, or a summary of the active filters once any are applied.

| Field              | Description                                                                                |
| ------------------ | ------------------------------------------------------------------------------------------ |
| Select Start Date  | The first day to retrieve entries for. Leave both dates empty to show the current day.     |
| Select End Date    | The last day to retrieve entries for. Requires a start date, and must fall on or after it. |
| Filter by Username | Restricts results to entries recorded against a particular user.                           |
| Filter by Severity | Restricts results to one or more severity levels. Several can be selected at once.         |

| Button        | Description                                                              |
| ------------- | ------------------------------------------------------------------------ |
| Apply Filters | Runs the query with the chosen filters and collapses the filter section. |
| Clear Filters | Resets every field and returns the table to the current day.             |

{% hint style="info" %}
Log entries are partitioned by date, and the day boundary follows your CIPP instance rather than your own location. The filter panel shows how far your local time is offset, which is worth checking when an entry you expect near midnight appears on the neighboring day.
{% endhint %}

{% hint style="warning" %}
Selecting a range of more than ten days produces an on-screen warning, because large ranges can time out or error given the volume of data being processed. Narrow the range if you run into problems.
{% endhint %}

{% hint style="info" %}
Debug entries are excluded unless you explicitly select Debug in **Filter by Severity**. If you have enabled Debug Mode to chase a problem and cannot see the output, this is usually why.
{% endhint %}

## Table Details

| Column    | Description                                                                                                                           |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------- |
| Date Time | The exact time the action was logged.                                                                                                 |
| Tenant    | The primary domain of the tenant the action relates to, or CIPP for platform-level entries.                                           |
| User      | The user associated with the action.                                                                                                  |
| Message   | A brief description of the action performed.                                                                                          |
| API       | The API endpoint or function that produced the entry.                                                                                 |
| Severity  | The severity level of the entry, as described below.                                                                                  |
| App Id    | The application ID of the API client that made the request, where the action came through an API client rather than a signed-in user. |
| IP        | The source IP address the request came from, where available.                                                                         |
| Log Data  | Additional structured data attached to the entry, where the logging call supplied any.                                                |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Log Entry</td><td>Opens the full logentry.md page for the selected entry, including any associated standard, template or scheduled task details.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

## Logbook Severity

| Severity | Description                                                                                                                                                                                                                                      |
| -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Alert    | A notable event that warrants proactive notification. Entries with this severity come from any alerts set up via alert-configuration.                                                                                                            |
| Error    | The operation failed. The requested action could not be completed, typically due to an API failure, missing permissions, or an invalid request.                                                                                                  |
| Info     | The operation completed successfully. Informational messages confirming an action was performed as expected.                                                                                                                                     |
| Warning  | The operation completed, but with a caveat. Something may need attention even though the action wasn't blocked. Example: resetting a password on a directory-synced user warns that password writeback must be enabled.                          |
| Critical | A platform-level failure occurred. Reserved for situations where CIPP's own infrastructure is impacted, such as failures retrieving tenant lists or GDAP relationships. These indicate a problem with CIPP itself, not a specific tenant action. |
| Debug    | Diagnostic information for troubleshooting. Only recorded when Debug Mode is enabled. Not included in notifications by default, and not returned unless Debug is selected in the severity filter.                                                |

{% include "../../../../.gitbook/includes/feature-request.md" %}
