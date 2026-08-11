# View Scheduled Task Details

This page shows everything recorded for a single scheduled task: how it is configured, when it runs, and the results of every execution so far.

The task's name is shown as the page heading.

## Action Buttons

<details>

<summary>View Logs</summary>

Opens a flyout showing the logbook entries recorded against this task, which is where to look when an execution failed and the result itself is not explanatory.

</details>

<details>

<summary>Actions</summary>

A menu carrying the same actions available on the scheduler list: **Run Now**, **Edit Job**, **Clone Job** and **Delete Job**. Which are shown depends on your scheduler permissions.

Unlike the list, **Edit Job** and **Clone Job** here navigate to the job page rather than opening the scheduler drawer.

</details>

## Details

The top card summarizes the task. Only the values that are set appear, so a task with no post-execution actions simply omits that row.

| Field          | Description                                                |
| -------------- | ---------------------------------------------------------- |
| Task State     | Whether the task is Planned, Running, Completed or Failed. |
| Command        | The command the task executes.                             |
| Tenant         | The tenant the task runs against.                          |
| Recurrence     | How often the task repeats.                                |
| Scheduled Time | When the task is next due to run.                          |
| Executed Time  | When the task last ran.                                    |
| Post Execution | Where the results are delivered after the task runs.       |

The refresh control on the card re-reads the task without reloading the page, which is useful while waiting on a run you have just triggered.

## Trigger Configuration

Shown only for tasks that have a trigger, this collapsible section lists the trigger's settings as recorded on the task.

## Task Parameters

Shown only where the task's command takes parameters, this collapsible section lists each parameter and the value the task passes.

## Execution Results

Every execution is listed as its own collapsible entry, headed with the tenant it ran against and a chip showing how long ago it ran. Where a task has run only once, that entry is expanded automatically.

How the result is displayed depends on what the command returned:

* A list of items renders as a table, paginated once there are more than ten rows.
* A structured result renders as a labelled property list.
* Anything else renders as plain text, preserving its original line breaks.
* An execution that returned nothing shows **No data available**.

A search box filters the history by tenant or by anything within the results themselves, and the heading shows how many entries match against the total. Where nothing matches, the section says so rather than appearing empty.

{% include "../../../../.gitbook/includes/feature-request.md" %}
