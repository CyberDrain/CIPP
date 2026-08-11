# Mailbox Activity

This report shows how much each mailbox in the selected tenant has actually been used over a chosen period, with one row per user. It counts messages sent, received, and read, along with meeting activity, which makes it useful for spotting dormant mailboxes before a license review.

## Filters

The **Report Period** section at the top of the page sets how far back the report reaches: 7, 30, 90, or 180 days. It defaults to 30 days. **Apply** reloads the report over the chosen period, and **Reset** returns it to 30 days.

## Table Details

The information displayed comes from the prebuilt Graph report `getEmailActivityUserDetail`. For additional details please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/reportroot-getemailactivityuserdetail?view=graph-rest-beta\&tabs=http).

{% hint style="info" %}
Microsoft usage reporting lags a day or two behind real time, so **Report Refresh Date** rather than today's date is the point the counts are accurate to. A mailbox created after that date has no row at all.
{% endhint %}

Selecting All Tenants queues the report as a background job, so the table stays empty with a queued message until every tenant has been collected.

## Anonymised Reports

Microsoft 365 has a tenant-wide setting that conceals user names in usage reports, replacing them with hashes rather than user principal names. Where CIPP detects that this report has come back anonymised, it shows a warning above the results.

The fix is on the tenant, not in CIPP. Enabling the **Enable Usernames instead of pseudo anonymised names in reports** standard turns the setting off, after which the report needs running again to pick up real names.

{% include "../../../../.gitbook/includes/feature-request.md" %}
