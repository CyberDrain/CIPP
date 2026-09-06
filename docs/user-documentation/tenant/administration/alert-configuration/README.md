# Alert Configuration

Alerts in CIPP come in two flavours, and both are listed here. Audit log alerts watch the Microsoft 365 audit log and fire as matching entries arrive. Scripted alerts run on a recurring schedule and check a specific condition each time they execute. This page shows every configured alert rule of both kinds, with the tenants they cover and what happens when they trigger, and lets you edit, clone, disable or remove them.

## Action Buttons

Use [alert.md](alert.md "mention") to create a new alert rule of either type.

## Table Details

| Column           | Description                                                                                                                                                                                                                              |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenants          | The tenants or tenant groups the alert is scoped to.                                                                                                                                                                                     |
| Event Type       | Whether the rule is an audit log alert (`Audit log Alert`) or a scripted alert that runs on a schedule (`Scheduled Task`).                                                                                                               |
| Enabled          | Whether the alert is currently live. A disabled alert keeps its full configuration but never triggers: audit log alerts stop matching incoming entries, and scripted alerts are skipped when their next run is due.                      |
| Conditions       | For audit log alerts, the configured conditions written out in plain language, joined with "and" when more than one is set. For scripted alerts, the name of the alert being run.                                                        |
| Repeats Every    | How often the alert runs. Audit log alerts show `When received`, as they fire as matching log entries arrive; scripted alerts show their configured recurrence.                                                                          |
| Actions          | What CIPP does when the alert triggers. For audit log alerts this is the list of chosen response actions, such as generating a ticket or disabling the user in the log entry. For scripted alerts it is the configured delivery method.  |
| Alert Comment    | The optional free-text comment saved with the alert.                                                                                                                                                                                     |
| Excluded Tenants | Any tenants or tenant groups left out of the alert's scope.                                                                                                                                                                              |

{% hint style="info" %}
Exclusions apply to both alert types and to any scope, including an alert that names its tenants individually. An excluded tenant group is resolved each time the alert runs, so a tenant added to that group is skipped from then on without editing the alert.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Task Details</td><td>Opens the underlying scheduled task, showing its run history and results. Greyed out for any row whose <strong>Event Type</strong> is not <code>Scheduled Task</code>.</td><td>false</td></tr><tr><td>Edit Alert</td><td>Opens the alert for editing so its tenants, conditions, schedule and actions can be adjusted and saved back over the existing rule.</td><td>false</td></tr><tr><td>Clone &#x26; Edit Alert</td><td>Opens a copy of the alert for editing, saving it as a new rule and leaving the original untouched. Useful for applying the same alert to a different set of tenants.</td><td>false</td></tr><tr><td>Enable Alert</td><td>Turns a disabled alert back on after confirmation, so it starts triggering again from the next matching log entry or scheduled run. Greyed out for alerts that are already enabled.</td><td>true</td></tr><tr><td>Disable Alert</td><td>Stops the alert triggering after confirmation, leaving its tenants, conditions and actions in place so it can be switched back on later. Greyed out for alerts that are already disabled.</td><td>true</td></tr><tr><td>Delete Alert</td><td>Removes the alert rule after confirmation. The alert stops firing immediately and cannot be recovered.</td><td>true</td></tr></tbody></table>

{% hint style="info" %}
Disabling is the reversible alternative to deleting. Editing a disabled alert and saving it keeps it disabled, so an alert stays off until you explicitly enable it again.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
