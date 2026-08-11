# Graph / Office Reports

This page gives you direct access to the usage and activity reports Microsoft publishes for a tenant, covering areas such as mailbox usage, OneDrive storage, Teams activity, and license assignment. Rather than curating a fixed set, CIPP asks the tenant which reports it offers and lists whatever comes back, so the selection reflects that tenant's own licensing and enabled services.

{% hint style="danger" %}
Not every report in this list will function for every tenant. The list of available reports is extensive and includes those that may not match tenant licensing, feature enablement, etc. Reports that are not available for a tenant will return a status code of 500.
{% endhint %}

## How to use this page

{% stepper %}
{% step %}
### Select Source

Choose between **Microsoft Graph** and **Office Reports (reports.office.com)**. The two draw on different reporting services and offer different reports, so it is worth checking both if you cannot find what you need. Microsoft Graph is selected by default.
{% endstep %}

{% step %}
### Select Available Report

The Report list is populated from the tenant based on your source selection. Changing the source clears the current report and reloads the list.
{% endstep %}

{% step %}
### Select Report Period

Choose how far back the report should reach: 7, 30, 90, or 180 days. This defaults to 30 days.

Period only applies to Microsoft Graph reports that accept a timeframe, so the selector is hidden for Office Reports and for the handful of Graph reports that return a current snapshot rather than a period of activity.
{% endstep %}

{% step %}
### Review Report

The report loads automatically. Changing the report or the period fetches a fresh copy. The results table supports the usual filtering and export options, so a report can be exported for a client or for further analysis.
{% endstep %}
{% endstepper %}

## Anonymised Reports

Microsoft 365 has a tenant-wide setting that conceals user and site names in usage reports, replacing them with hashes rather than user principal names. Where CIPP detects that a report has come back anonymised, it shows a warning above the results.

The fix is on the tenant, not in CIPP. Enabling the **Enable Usernames instead of pseudo anonymised names in reports** standard turns the setting off, after which the report needs running again to pick up real names.

{% hint style="info" %}
This setting also affects reports elsewhere in CIPP, and in the Microsoft 365 admin center itself, so it is worth resolving for any tenant where you rely on usage reporting.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
