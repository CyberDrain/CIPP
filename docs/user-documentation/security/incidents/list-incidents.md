---
description: Triage Microsoft Defender security incidents across your Microsoft 365 tenants.
---

# Incidents

Security incidents raised in Microsoft Defender for the selected tenant, each one grouping the related alerts behind a single case. Work the queue from here: take an incident, move it through its statuses, adjust its severity, and open it in the Defender portal when you need the full attack story.

## Filters

A date filter sits above the table. Set a **Start Date**, an **End Date**, or both, then select **Apply** to reload the table for that window. Leaving one side empty makes the window open ended in that direction. **Clear** removes the filter and returns every incident.

The page opens with the filter already set to the last 30 days, so an unfiltered view is something you ask for rather than what you land on.

## Table Details

| Column | Description |
| ------------- | -------------------------------------------------------------------------------------------------------- |
| Created       | When the incident was raised.                                                                              |
| Id            | Microsoft's incident identifier. Quote it when comparing against the Defender portal.                      |
| Display Name  | The incident's name in Defender.                                                                           |
| Status        | Where the incident sits in triage, as reported by Defender. The table actions move it between active, in progress and resolved. |
| Severity      | Defender's severity rating for the incident.                                                               |
| Assigned To   | Who currently owns the incident, or empty when nobody has taken it.                                        |
| Tags          | The tags applied to the incident, joined into one cell.                                                    |
| Incident Url  | A direct link to the incident in the Defender portal.                                                      |

The Extended Info flyout adds the last updated time, the classification and determination recorded on the incident, and the redirect identifier, which is filled in when Defender has merged this incident into another one.

{% hint style="info" %}
Selecting All Tenants queues a background job that collects incidents from every tenant, and the page tells you it is still loading. Come back in a few minutes for a complete list.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View in Defender</td><td>Opens the incident in the Microsoft Defender portal in a new tab. Greyed out when the incident has no <strong>Incident Url</strong>.</td><td>false</td></tr><tr><td>Assign to self</td><td>Puts your name on the incident as its owner.</td><td>true</td></tr><tr><td>Set status to active</td><td>Moves the incident back into the active queue.</td><td>true</td></tr><tr><td>Set status to in progress</td><td>Marks the incident as being worked on.</td><td>true</td></tr><tr><td>Set status to resolved</td><td>Closes the incident, with an optional <strong>Resolving comment</strong> recorded against it.</td><td>true</td></tr><tr><td>Set severity</td><td>Changes the incident's severity, prompting you to choose <code>Informational</code>, <code>Low</code>, <code>Medium</code> or <code>High</code>.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
