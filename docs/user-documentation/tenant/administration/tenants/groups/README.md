# Tenant Groups

Lists your custom tenant groups and gives you the tools to create and maintain them. Tenant groups are logical groupings of managed tenants that can be selected anywhere CIPP asks for a tenant filter, which saves you picking the same set of tenants by hand every time. A group is either static, where you choose its members explicitly, or dynamic, where CIPP evaluates a set of rules against your tenants and works out the membership for you.

## Action Buttons

<details>

<summary>Add Tenant Group</summary>

Opens a flyout to create a new tenant group. Set the group name, description, and group type, then either pick the initial member tenants for a static group or build the membership rules for a dynamic group. Dynamic groups also offer the option to exclude the partner tenant from the group even when the membership rules would otherwise include it. The fields are the same as those on the edit page, so see edit.md for the full detail on configuring a group.

</details>

<details>

<summary>Show Usage / Hide Usage</summary>

Toggles the Usage column in the table. Leaving it off keeps the page quicker to load, since working out usage means reading through your templates, tasks, rules, roles, and mappings. See the Usage entry under Table Details for what it reports.

</details>

<details>

<summary>Create Default Groups</summary>

Creates a predefined set of dynamic tenant groups provided by CIPP, intended as ready made starting points for standards templates. Any group whose name already exists is skipped rather than overwritten, so it is safe to run more than once. You are asked to confirm before the groups are created.

| Name                                      | What it matches                                                                                                                 |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Not Intune and Entra Premium Capable      | Tenants with neither a Microsoft Intune service plan nor a Microsoft Entra ID P1 service plan available.                        |
| Business Premium License available        | Tenants with at least one Microsoft 365 Business Premium license available, including the no Teams, EEA, and donation variants. |
| Entra Premium Capable, Not Intune Capable | Tenants with a Microsoft Entra ID P1 service plan available but no Microsoft Intune service plan.                               |
| Entra ID Premium and Intune Capable       | Tenants with both Microsoft Intune and Microsoft Entra ID P1 service plans available.                                           |
| All Tenants (Excluding Partner)           | Every tenant managed through a GDAP or direct relationship, with the partner tenant itself excluded.                            |

</details>

<details>

<summary>View Logs</summary>

Opens a flyout showing CIPP's own log entries for tenant group activity, covering things like dynamic rule runs, group creation, and any failures encountered while processing them.

</details>

## How to Make a Dynamic Tenant Group

{% @storylane/embed subdomain="app" url="https://app.storylane.io/share/idk6ryipa9ch" linkValue="idk6ryipa9ch" %}

## Table Details

| Column      | Description                                                                                                                                                                                                                                                                    |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Name        | The name of the group.                                                                                                                                                                                                                                                         |
| Description | The description set for the group.                                                                                                                                                                                                                                             |
| Group Type  | Whether the group is `static`, with membership you set explicitly, or `dynamic`, with membership evaluated from rules.                                                                                                                                                         |
| Members     | The tenants currently in the group. For a dynamic group this reflects the last rule evaluation rather than a live check.                                                                                                                                                       |
| Usage       | Where the group is currently referenced elsewhere in CIPP, naming each item and how it is used. Covers standards templates, scheduled tasks, alert rules, custom roles, custom data mappings, and the rules of other dynamic groups. Only shown when Show Usage is toggled on. |

{% hint style="info" %}
Check the Usage column before deleting a group. A group that is still referenced by a standards template or a custom role will leave that reference pointing at nothing once removed.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Group</td><td>Opens the edit.md page for the selected group, where you can change its name, description, and membership or rules.</td><td>false</td></tr><tr><td>Run Dynamic Rules</td><td>Forces an immediate re-evaluation of the group's membership rules rather than waiting for the next scheduled run. Only offered on groups with a dynamic group type. You are asked to confirm before the rules are run.</td><td>true</td></tr><tr><td>Delete Group</td><td>Permanently removes the selected group. You are asked to confirm before the group is deleted.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
