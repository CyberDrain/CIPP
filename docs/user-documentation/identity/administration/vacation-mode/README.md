# Vacation Mode

Vacation Mode schedules temporary changes to a user's access and mailbox for a fixed period, then reverses them automatically when the period ends. It covers Conditional Access exclusions, location-based audit log alert exclusions, temporary group membership, mailbox delegation, mail forwarding, and out of office replies, so a single schedule can cover everything that needs to change while someone is away.

Each vacation produces a pair of scheduled tasks for every change: one that applies it at the start date and one that reverses it at the end date. This page lists those tasks.

## Vacation Mode In Action

{% @storylane/embed subdomain="app" url="https://app.storylane.io/share/d7llhd4j78qv" linkValue="d7llhd4j78qv" %}

## Action Buttons

<details>

<summary>Add Vacation Schedule</summary>

Opens the add-vacation-schedule.md wizard, where the users, the changes to apply and the dates are chosen.

</details>

## Filters

| Filter              | Shows                                                                                    |
| ------------------- | ---------------------------------------------------------------------------------------- |
| Running             | Tasks currently executing.                                                               |
| Planned             | Tasks scheduled but not yet run, which includes every reversal waiting for its end date. |
| Failed              | Tasks that did not complete.                                                             |
| Completed           | Tasks that have run successfully.                                                        |
| CA Exclusion        | Tasks that add or remove a Conditional Access policy exclusion.                          |
| Location Alerts     | Tasks that add or remove a location-based audit log alert exclusion.                     |
| Mailbox Permissions | Tasks that grant or revoke mailbox delegation.                                           |
| Mail Forwarding     | Tasks that set or clear mail forwarding.                                                 |
| Out of Office       | Tasks that enable or disable automatic replies.                                          |
| Group Membership    | Tasks that add or remove users from groups for the vacation.                             |

## Table Details

| Column         | Description                                                                                                  |
| -------------- | ------------------------------------------------------------------------------------------------------------ |
| Tenant         | The tenant the task runs against.                                                                            |
| Name           | What the task does, including whether it applies or reverses the change and which user or policy it affects. |
| Reference      | The reference entered when the schedule was created, which ties the tasks of one vacation together.          |
| Task State     | Whether the task is planned, running, completed or failed.                                                   |
| Scheduled Time | When the task is due to run.                                                                                 |
| Executed Time  | When the task actually ran. Empty for a task still waiting.                                                  |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Task Details</td><td>Opens the <a data-mention href="../../../tools/scheduler/task.md">task.md</a> page for the selected task, showing its full parameters and results.</td><td>false</td></tr><tr><td>Cancel Vacation Mode</td><td>Removes the selected scheduled task so it never runs.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="danger" %}
Cancelling is per task, not per vacation. Cancelling the task that reverses a change leaves that change in place permanently: an excluded user stays excluded, a delegate keeps their access, forwarding keeps forwarding. To call off a vacation that has already started, cancel the reversal only if you intend the change to be permanent, and otherwise let it run or undo the change by hand.
{% endhint %}

{% hint style="info" %}
Because a vacation is several independent tasks rather than one object, use the **Reference** column to find every task belonging to the same schedule before cancelling anything.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
