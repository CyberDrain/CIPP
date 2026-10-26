# Teams Activity

Shows an overview of your users and their activity in Teams, allowing you to gain a broader understanding of usage and target certain users for Teams training. The information provided here covers the last 30 days.

## Table Details

| Column        | Description                                                                                  |
| ------------- | ---------------------------------------------------------------------------------------------- |
| UPN           | The user principal name of the user.                                                         |
| Last Active   | The last date the user was active in Teams. Blank when they have had no activity.            |
| Meeting Count | The number of meetings the user took part in over the reporting period.                      |
| Call Count    | The number of calls the user took part in over the reporting period.                         |
| Teams Chat    | The number of messages the user posted in team chats over the reporting period.              |

## Anonymised Reports

Microsoft 365 has a tenant-wide setting that conceals user names in usage reports, replacing them with hashes rather than user principal names. Where CIPP detects that this report has come back anonymised, it shows a warning above the results.

The fix is on the tenant, not in CIPP. Enabling the **Enable Usernames instead of pseudo anonymised names in reports** standard turns the setting off, after which the report needs running again to pick up real names.

{% include "../../../../.gitbook/includes/feature-request.md" %}
