# Pending with Issues

Pending with Issues lists planned tasks that would fail if they ran right now, so you can fix the problem before the scheduled time arrives rather than finding out afterwards. The typical case is a user creation scheduled for a new starter's first day, where the licence it needs has been used up in the meantime.

CIPP checks planned tasks every six hours. A task that would fail is flagged with the reason, for example "no licences available for Microsoft 365 E5 Developer", and appears here. The flag clears on its own when the problem goes away, when the task is edited, or once the task actually runs.

{% hint style="info" %}
Tasks that buy their licence through Sherweb at run time are not flagged, since the licence does not need to exist in the tenant beforehand.
{% endhint %}

## Fixing a Flagged Task

Buy or free up the licence the task needs, then either wait for the next six-hourly check or use **Re-check Now** to update the list immediately. If the problem is real but expected, you can also edit the task to use a different licence, or reschedule it for after the licences arrive.

A flag is a forecast, not a block. A flagged task still runs at its scheduled time and simply tries; if the licence has come back by then, it succeeds as normal.

## Action Buttons

<details>

<summary>Re-check Now</summary>

Runs the availability check immediately instead of waiting for the next six-hourly pass. Use this after buying or freeing licences so the list reflects reality straight away.

</details>

## Table Details

| Column         | Description                                                          |
| -------------- | -------------------------------------------------------------------- |
| Scheduled Time | When the task is due to run                                          |
| Task State     | Always Planned while a task is in this view                          |
| At Risk Reason | Why the task is expected to fail, named against the licence involved |
| Tenant         | The tenant the task runs against                                     |
| Name           | The task's name                                                      |
| Command        | The command the task runs                                            |

## Notifications

Flagged tasks can raise a notification through the standard pipeline. Select "Tasks pending with issues" under the log types in [notifications.md](../../cipp/settings/notifications.md "mention"). A task is alerted once when it becomes flagged, not repeatedly while it stays flagged.

***

{% include "../../../../.gitbook/includes/feature-request.md" %}
