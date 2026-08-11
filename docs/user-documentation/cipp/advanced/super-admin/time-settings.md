# Time Settings

This page will allow you to modify certain time settings for how CIPP will operate.

## Timezone

This dropdown will allow you to set the time zone for CIPP operations and scheduling.

The time zone determines when scheduled tasks and background jobs run, and which day log entries are grouped under.

{% hint style="info" %}
If you have not selected a time zone, CIPP defaults to the time zone of the Azure region it is deployed in — an instance in East US defaults to `America/New_York`, one in West Europe to `Europe/Amsterdam`. If the region cannot be determined, UTC is used.

A time zone you select here always takes precedence and is never replaced by that automatic default.
{% endhint %}

{% hint style="warning" %}
This affects CIPP's own background jobs that run at a fixed time of day — Standards, Drift detection, the Domain Analyzer, tenant refresh, and the nightly cleanup and reporting jobs. Changing the time zone moves them: a job that ran at 03:00 UTC will run at 03:00 in the new time zone instead.

It does **not** change Scheduled Tasks that you create yourself. Those run at the absolute time you picked when you created them. Background jobs that run on a short interval, such as every 15 minutes, are also unaffected.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
