# Scheduler

The task scheduler allows you to schedule CIPP functionality to be executed at a later date, and send the results to your PSA, Webhook, or email.

The scheduler allows you to schedule components to run once, every day, every 7 days, every 30 days, or every year.

The scheduler has three tabs. All Tasks is the full list described on this page. [failed-queue.md](failed-queue.md "mention") shows tasks that failed or completed with errors and need attention. [pending-with-issues.md](pending-with-issues.md "mention") shows planned tasks that are expected to fail, such as a user creation whose licence is no longer available, so they can be fixed before they run.

{% hint style="warning" %}
Scheduling a task for the past will make it run on the next interval the scheduler runs.
{% endhint %}

Scheduled tasks can be used to run tasks at 15 minute intervals. The system does not allow you to schedule a task for any other intervals. If you add a task via the API for 10:10, the task will run at 10:15.

A recurring task will return to a planned state directly after execution. The latest results of a task can be viewed via the eye icon in the history table.

## Action Buttons

<details>

<summary>Show/Hide System Jobs</summary>

Depending on which is displayed, this will either show or hide the system jobs in the table below

</details>

<details>

<summary>Add Job</summary>

Opens the [job.md](job.md "mention") page

</details>

## Table Details

| Column         | Description                                                                     |
| -------------- | ------------------------------------------------------------------------------- |
| Executed Time  | The relative time since the task was last run                                   |
| Task State     | "Planned", "Running", "Completed", "Failed", or "Failed - Planned"              |
| Has Errors     | Whether the last run recorded any errors, even if the task completed            |
| At Risk        | Whether the task is expected to fail when it runs                               |
| Tenant         | The tenant selected for the job                                                 |
| Name           | The job's name                                                                  |
| Scheduled Time | The relative time since the task ran or until the task is scheduled to run next |
| Command        | The command selected for the task                                               |
| Post Execution | The settings for post execution notification                                    |
| Recurrence     | The recurrence selected for the task                                            |
| Results        | The results of the most recently run execution of the task                      |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Task Details</td><td>Will open a view only page with the full details of the job</td><td>false</td></tr><tr><td>Run Now</td><td>Will run the task at the next quarter hour</td><td>true</td></tr><tr><td>Acknowledge Errors</td><td>Shown on tasks that failed or completed with errors. Marks the failure as dealt with and removes the task from the Failed Queue while keeping its error details. See <a href="failed-queue.md">failed-queue.md</a></td><td>false</td></tr><tr><td>Edit Job</td><td>Will display the job in a state where you can edit the details</td><td>false</td></tr><tr><td>Clone and Edit Job</td><td>Creates a copy of the selected job and opens the edit window to make any necessary changes</td><td>false</td></tr><tr><td>Delete Job</td><td>Deletes the job from the schedule</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

## Task Details

This flyout displays more details on the scheduled task.

### Action Buttons

<details>

<summary>View Logs</summary>

This will open a separate flyout that will show the logbook entry for the scheduled task.

</details>

<details>

<summary>Actions</summary>

Select to "Run Now", "Edit Job", "Clone Job", or "Delete Job"

</details>

### Details

This will include the top-level information on the task, such as status, the command being run, etc.

### Task Parameters

Expand this section to view the parameters used for this task's command.

### Execution Results

This table will display the history of the task's execution.

***

{% include "../../../../.gitbook/includes/feature-request.md" %}
