# Teams

The Teams page lists every team in the selected tenant, with its name, description, and whether it is a public or private team. From here you can open a team's underlying Microsoft 365 group to edit it, or delete a team outright.

## Action Buttons

{% content-ref url="add.md" %}
[add.md](add.md)
{% endcontent-ref %}

## Table Details

The properties returned are for the Graph resource type `group`, filtered to groups that have been Teams-enabled. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/group?view=graph-rest-beta#properties).

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Team</td><td>Opens the team's <a data-mention href="../../../identity/administration/groups/team.md">team.md</a> tab on its group page, to change team settings, archive the team and manage its channels, channel members and tabs.</td><td>false</td></tr><tr><td>Edit Group</td><td>Opens the team's underlying Microsoft 365 group in the <a data-mention href="../../../identity/administration/groups/edit.md">edit.md</a> page, where its members, owners, and settings can be changed.</td><td>false</td></tr><tr><td>Delete Team</td><td>Deletes the selected team by deleting its underlying Microsoft 365 group, which takes the team's channels, SharePoint site, and shared mailbox with it. You are asked to confirm first. The group and its content stay recoverable for 30 days before being permanently removed.</td><td>true</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
