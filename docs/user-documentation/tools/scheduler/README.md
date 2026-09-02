# Scheduler

The task scheduler runs CIPP functionality on a schedule and delivers the results to your PSA, a webhook, or email.

Tasks can run once, or repeat every day, 7 days, 30 days, or year.

{% hint style="warning" %}
Scheduling a task in the past makes it run at the next interval the scheduler runs.
{% endhint %}

The scheduler operates on 15-minute intervals, and no other cadence is available. A task created through the API for 10:10 runs at 10:15. A recurring task returns to a planned state immediately after it executes.

A banner above the table counts down to the next scheduler run, shows the time it is due, and reports how many tasks that run will pick up. A task whose scheduled time has already passed stays **Planned** until that run, so a time in the recent past is not a sign the task has failed.

The count covers the tasks currently listed, so it follows the **Show System Jobs** toggle: with system jobs hidden it counts only your own tasks. Tasks in a stuck state that the scheduler recovers on its own are not included.

A second count appears whenever tasks are already being worked on. Once the scheduler picks a task up it leaves **Planned** and stops being due, so it moves out of the due count and is reported as in progress until it finishes. A task shown as **Pending** has therefore already been claimed rather than being sat waiting for the next run.

## Action Buttons

<details>

<summary>Show System Jobs</summary>

Reveals the tasks CIPP schedules for itself alongside your own and becomes **Hide System Jobs** once shown. These are hidden by default because they are numerous and rarely need attention.

</details>

<details>

<summary>Add Task</summary>

Opens the **Add Task** drawer, which builds a scheduled task without leaving this page. The same drawer is reused for **Edit Job** and **Clone Job**, retitled accordingly.

Every task needs a tenant, a name, and a command. The rest depends on which of the two task types you pick.

| Field                  | Description                                                                                                                                          |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Select a Tenant        | The tenant the task runs against. All Tenants and tenant groups are both selectable, so one task can cover a whole estate.                           |
| Task Name              | The name the task appears under in the table.                                                                                                        |
| Post Execution Actions | Where the results go once the task has run. Choose any combination of Webhook, Email, and PSA, or none to leave the results on the task itself.      |
| PSA Ticket Strategy    | How many tickets the task raises. Only shown once PSA is among the post execution actions.                                                           |
| Reference              | An optional note identifying the task. It is also added to the title of any notification the task sends, which makes it useful for routing in a PSA. |

**PSA Ticket Strategy** overrides the HaloPSA **Link Tickets to affected Users** toggle for this task alone, which is useful for a task with a wide result set, such as a list of users without MFA, where the number of tickets raised matters.

| Option                             | Description                                                   |
| ---------------------------------- | ------------------------------------------------------------- |
| One ticket per affected user       | Raises a separate ticket for each user in the task's results. |
| One consolidated ticket per tenant | Raises a single ticket per tenant listing every result.       |

Whichever option matches the current HaloPSA integration setting is labelled as the integration default, so you can see what the task would do before changing it.

{% hint style="info" %}
The field always holds one of the two options rather than an inherited setting. Selecting PSA and saving therefore fixes a strategy on the task even if you never opened the dropdown, and that strategy stays with the task afterwards regardless of how the integration setting is later changed.
{% endhint %}

A pair of buttons then selects the task type:

**Scheduled Task** runs on a clock. A **Schedule Configuration** section asks for a **Start Date** and a **Recurrence** of Once, or every 1, 7, 14, 21, 30, or 365 days. The recurrence field also accepts a value you type yourself for intervals outside that list.

**Triggered Task** runs in response to a change in the tenant rather than on a fixed schedule. A **Trigger Configuration** section defines what to watch:

| Field                        | Description                                                                                               |
| ---------------------------- | --------------------------------------------------------------------------------------------------------- |
| Trigger Type                 | The kind of trigger. Delta Query is currently the only option, which watches Microsoft Graph for changes. |
| Resource Type                | What to watch, such as Users, Groups, Devices, Applications, Service Principals, or Directory Roles.      |
| Event Type                   | Which change fires the task: Resource Created, Resource Updated, or Resource Deleted.                     |
| Filter Specific Resources    | Optional conditions narrowing which resources count, each a property, an operator, and a value.           |
| Attributes to Monitor        | Restricts an update trigger to changes affecting particular attributes.                                   |
| Execute Command Per Resource | Runs the command once for each matching resource rather than once for the batch.                          |
| Execution Mode               | How the command is executed against the matched resources.                                                |
| Check Frequency              | How often CIPP checks for changes: every 15 or 30 minutes, or every 1, 4, 12, or 24 hours.                |

Both task types then share a **Command & Parameters** section. Choose a command from the list, and the drawer renders the fields that command takes so you can fill them in directly. A refresh control beside the picker re-reads the available commands.

Where a command takes something the form cannot render, **Use advanced parameters** replaces the generated fields with an **Advanced Parameters (JSON Input)** box for supplying the parameters as JSON.

Each section shows a one-line summary of its current settings in its header, so a collapsed drawer still reads as a complete description of the task.

</details>

## Filters

| Filter    | Shows                                                |
| --------- | ---------------------------------------------------- |
| Running   | Tasks that are currently running.                    |
| Planned   | Tasks that are waiting for their next scheduled run. |
| Failed    | Tasks whose most recent run failed.                  |
| Completed | Tasks whose most recent run completed successfully.  |

## Table Details

Preset filters above the table narrow the list to tasks that are **Running**, **Planned**, **Failed**, or **Completed**.

| Column         | Description                                                                                   |
| -------------- | --------------------------------------------------------------------------------------------- |
| Executed Time  | The relative time since the task last ran.                                                    |
| Task State     | Whether the task is Planned, Running, Completed, or Failed.                                   |
| Tenant         | The tenant the task runs against.                                                             |
| Name           | The task's name.                                                                              |
| Scheduled Time | The relative time since the task ran, or until it is next due to run.                         |
| Command        | The command the task executes.                                                                |
| Parameters     | The parameters passed to that command.                                                        |
| Post Execution | Where the results are delivered after the task runs.                                          |
| Reference      | The reference recorded against the task, used to identify it in logging and delivered output. |
| Recurrence     | How often the task repeats.                                                                   |
| Results        | The results of the most recent execution.                                                     |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Task Details</td><td>Opens the full read-only <a data-mention href="task.md">task.md</a> page for the task.</td><td>false</td></tr><tr><td>Run Now</td><td>Queues the task to run at the next quarter hour rather than waiting for its schedule.</td><td>true</td></tr><tr><td>Edit Job</td><td>Opens the <a data-mention href="./#add-task">#add-task</a> drawer with the task loaded for editing.</td><td>true</td></tr><tr><td>Clone Job</td><td>Opens the <a data-mention href="./#add-task">#add-task</a> drawer with a copy of the task, ready to adjust and save as a new one.</td><td>true</td></tr><tr><td>Delete Job</td><td>Removes the task from the schedule.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
The actions available depend on your permissions. Viewing task details requires read access to the scheduler; running, editing, cloning, and deleting all require read and write access, and are hidden otherwise.
{% endhint %}

## Task Details

The flyout shows the full picture for a single task.

### Action Buttons

<details>

<summary>View Logs</summary>

Opens a further flyout showing the logbook entries recorded for this task.

</details>

<details>

<summary>Actions</summary>

The same set of actions available on the table row: Run Now, Edit Job, Clone Job, and Delete Job.

</details>

### Sections

| Section               | Description                                                                                                                                                              |
| --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Details               | The task's top-level information, including its state, the command being run, and the tenant it targets. A refresh control re-reads the task without reloading the page. |
| Trigger Configuration | How and when the task fires.                                                                                                                                             |
| Task Parameters       | The parameters passed to the task's command.                                                                                                                             |
| Execution Results     | The history of the task's executions, with a count of how many entries are shown against the total and a search box for narrowing a long history.                        |

{% include "../../../../.gitbook/includes/feature-request.md" %}
