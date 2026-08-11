# Timers

CIPP runs its background work on a set of scheduled timers, covering things like processing user scheduled tasks, audit log collection, standards runs, and internal housekeeping. This page shows every timer, the schedule it runs on, when it last ran and when it is next due, and lets you trigger one immediately or restore all schedules to their defaults.

Schedules are cron expressions, accepting either the standard five field form or a six field form that includes seconds. They are evaluated against the timezone configured for your instance, falling back to UTC where none is set.

## Table Details

| Column              | Description                                                                                                                              |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Priority            | The order in which timers are processed when several are due at the same time. Lower numbers run first.                                  |
| Command             | The CIPP function the timer executes.                                                                                                    |
| Parameters          | Any parameters passed to that function, where the timer defines them.                                                                    |
| Cron                | The schedule the timer runs on.                                                                                                          |
| Next Occurrence     | When the timer is next due to run.                                                                                                       |
| Last Occurrence     | When the timer last ran, or Never if it has not run yet.                                                                                 |
| Status              | The state of the most recent run. Timers that have been registered but have not yet run show as Not Scheduled.                           |
| Preferred Processor | The offloaded processor node the timer prefers to run on, where one is nominated. Timers without a preference run on any available node. |
| Error Msg           | The error recorded by the most recent run, where one failed.                                                                             |

{% hint style="info" %}
This page lists every timer CIPP defines, including those tied to features that are currently disabled. A timer belonging to a disabled feature appears here but is skipped when schedules are evaluated, so a stale **Last Occurrence** on such a timer is expected rather than a fault.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Run Now</td><td>Executes the timer's function immediately with its configured parameters, without waiting for the next scheduled occurrence.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
**Run Now** starts the work straight away and does not check whether that timer is already running. Triggering a long-running timer repeatedly, or in bulk across several timers, can leave overlapping runs competing for the same resources. Give a run time to finish before starting another.
{% endhint %}

## Reset to Default

**Reset to Default** discards any customized schedules and restores the timings CIPP ships with. You are asked to confirm before it applies.

{% hint style="warning" %}
This applies to every timer at once. There is no way to reset an individual schedule, and no record is kept of what the customized values were, so note anything you want to reinstate before resetting.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
