# Failed Queue

The Failed Queue lists every scheduled task that needs attention: tasks that failed outright, recurring tasks whose last run failed, and tasks that completed while a step inside them failed. That last group matters most. A scheduled user creation can create the user but fail to assign the licence, and the task itself still completes; the Failed Queue is where that surfaces instead of hiding inside the task's results.

A task leaves the queue when a later run succeeds, when it is edited (editing resets it to a clean planned task), when it is deleted, or when you acknowledge it.

## Task States

| State            | Meaning                                                                                                        |
| ---------------- | -------------------------------------------------------------------------------------------------------------- |
| Failed           | The task ran and failed. One-time tasks stay in this state until acted on.                                     |
| Failed - Planned | A recurring task whose last run failed. It stays in the schedule and runs again at its next interval.          |
| Completed        | The task finished, but a step inside it failed. Check Error Summary for what went wrong.                       |

## Table Details

| Column        | Description                                                                    |
| ------------- | ------------------------------------------------------------------------------ |
| Executed Time | The relative time since the task last ran                                      |
| Task State    | See the states above                                                           |
| Has Errors    | Whether the last run recorded any errors                                       |
| Error Summary | What went wrong on the last run, in the words of the error that was logged     |
| Tenant        | The tenant the task runs against                                               |
| Name          | The task's name                                                                |
| Command       | The command the task runs                                                      |
| Results       | The results of the most recent run                                             |

## Acknowledging a Failure

If you have fixed the underlying problem outside CIPP, for example by assigning the missing licence to the user directly, the task row itself is still a record of a failure. Acknowledge Errors marks it as dealt with: the row leaves this queue, but keeps its error details and records who acknowledged it and when.

{% hint style="info" %}
An acknowledgement is cleared automatically if the task fails again on a later run, so a recurring problem comes back to the queue rather than staying dismissed.
{% endhint %}

{% hint style="warning" %}
Run Now on a completed user-creation task will fail with a duplicate username error, because the user already exists. For those, fix the user directly and acknowledge or delete the task. Run Now is the right tool for idempotent tasks such as a failed licence assignment.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Task Details</td><td>Will open a view only page with the full details of the job</td><td>false</td></tr><tr><td>Run Now</td><td>Will run the task at the next quarter hour</td><td>true</td></tr><tr><td>Acknowledge Errors</td><td>Marks the failure as dealt with and removes the task from this queue. The error details stay on the task.</td><td>false</td></tr><tr><td>Edit Job</td><td>Will display the job in a state where you can edit the details</td><td>false</td></tr><tr><td>Clone and Edit Job</td><td>Creates a copy of the selected job and opens the edit window to make any necessary changes</td><td>false</td></tr><tr><td>Delete Job</td><td>Deletes the job from the schedule</td><td>true</td></tr></tbody></table>

***

{% include "../../../../.gitbook/includes/feature-request.md" %}
