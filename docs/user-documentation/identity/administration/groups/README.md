---
description: Interact with Microsoft 365 groups.
---

# Groups

The Groups page lists every group in the tenant and is where group membership, mail behaviour and lifecycle are managed. It covers the same ground as [Microsoft 365 admin center > Active teams and groups](https://admin.microsoft.com/#/groups), and extends it with actions that would otherwise need Exchange Online PowerShell.

## Action Buttons

**Add Group** creates a group in the selected tenant, and **Deploy Group Template** applies a saved template to one or more tenants.

{% content-ref url="add.md" %}
[add.md](add.md)
{% endcontent-ref %}

{% content-ref url="../group-templates/deploy.md" %}
[deploy.md](../group-templates/deploy.md)
{% endcontent-ref %}

{% content-ref url="edit.md" %}
[edit.md](edit.md)
{% endcontent-ref %}

## Table Details

| Column                       | Description                                                                                                                                   |
| ---------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name                 | The name of the group as it appears throughout Microsoft 365.                                                                                 |
| Description                  | The group's description.                                                                                                                      |
| Mail                         | The group's email address, where it has one.                                                                                                  |
| Mail Enabled                 | Whether the group can receive email.                                                                                                          |
| Mail Nickname                | The alias the group's address is built from.                                                                                                  |
| Group Type                   | The kind of group, worked out by CIPP from the group's underlying flags: Microsoft 365, Mail-Enabled Security, Security or Distribution List. |
| Assigned Licenses            | Licences assigned to the group for group-based licensing.                                                                                     |
| License Processing State     | How far Entra has got with applying group-based licences to the members.                                                                      |
| Visibility                   | Whether the group is public or private.                                                                                                       |
| On Premises Sam Account Name | The account name the group carries when it is synchronised from on-premises Active Directory.                                                 |
| Membership Rule              | The rule that decides membership, for a dynamic group.                                                                                        |
| On Premises Sync Enabled     | Whether the group is synchronised from on-premises Active Directory.                                                                          |
| Members                      | The group's members, reached through a **View members** button.                                                                               |
| Owners                       | The group's owners, reached through a **View owners** button.                                                                                 |
| Has Owner                    | Whether the group has at least one owner.                                                                                                     |

{% hint style="info" %}
Group Type is composed by CIPP rather than returned by Graph, which reports the same information across the `groupTypes`, `mailEnabled` and `securityEnabled` properties. A group is Microsoft 365 when its `groupTypes` include `Unified`, Mail-Enabled Security when it is both mail and security enabled, Security when it is security enabled alone, and a Distribution List when it is mail enabled alone. This matters when comparing against Graph output or the Entra portal, where no single equivalent field exists.
{% endhint %}

## Members and Owners

The **Members** and **Owners** columns each open the group's list in a dialog, so membership can be reviewed and changed without leaving the Groups page. Selecting rows inside a dialog makes the removal action available across all of them at once. While the table is showing cached data the two columns list user principal names as text instead, and the buttons are not offered.

<details>

<summary>View members</summary>

Opens a dialog headed with the group's name, listing everything that belongs to it. A group can hold nested groups, devices and service principals as well as users, so the list is not always people.

| Column              | Description                                                                       |
| ------------------- | --------------------------------------------------------------------------------- |
| Display Name        | The member's name.                                                                |
| User Principal Name | The member's sign-in name, where it has one.                                      |
| Mail                | The member's email address, where it has one.                                     |
| Type                | The kind of directory object the member is, for example a user or a nested group. |

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View User</td><td>Opens the <a data-mention href="../users/user/">user</a> page for the member. Greyed out for members that are not users.</td><td>false</td></tr><tr><td>View Group</td><td>Opens the <a data-mention href="group.md">group.md</a> page for a nested group. Greyed out for members that are not groups.</td><td>false</td></tr><tr><td>Remove Member</td><td>Takes the member out of the group. Greyed out when the group's membership is set by a rule, because a dynamic group's membership can only be changed by editing the rule.</td><td>true</td></tr></tbody></table>

**Add Members** takes one or more users or groups, picked from the tenant list or uploaded as a CSV with a `userPrincipalName` column. It is not offered for a dynamic group.

</details>

<details>

<summary>View owners</summary>

Opens a dialog headed with the group's name, listing the people who own it.

| Column              | Description                                   |
| ------------------- | --------------------------------------------- |
| Display Name        | The owner's name.                             |
| User Principal Name | The owner's sign-in name.                     |
| Mail                | The owner's email address, where they have one. |

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View User</td><td>Opens the <a data-mention href="../users/user/">user</a> page for the owner.</td><td>false</td></tr><tr><td>Remove Owner</td><td>Takes the owner off the group.</td><td>true</td></tr></tbody></table>

**Add Owners** takes one or more users, picked from the tenant list or uploaded as a CSV with a `userPrincipalName` column. Anyone already listed as an owner is reported back as skipped, and the rest of the selection is still added.

{% hint style="info" %}
Owners of a Distribution List or Mail-Enabled Security group are held by Exchange rather than Entra, so a change made here appears as the group's **Managed By** list in Exchange Online.
{% endhint %}

</details>

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Group</td><td>Opens the <a data-mention href="group.md">group.md</a> page for the group, covering its membership, owners and settings.</td><td>false</td></tr><tr><td>Edit Group</td><td>Opens the <a data-mention href="edit.md">edit.md</a> page, where membership, owners and group settings can be changed.</td><td>false</td></tr><tr><td>Add Member</td><td>Adds one or more users to the group. Pick them from the tenant user list, or drop a CSV file with a <code>userPrincipalName</code> column to add members in bulk. Selecting several groups adds the same users to each of them. Greyed out for a dynamic group or one synchronised from on-premises Active Directory, since manual member changes are rejected for both.</td><td>true</td></tr><tr><td>Set Global Address List Visibility</td><td>Hides the group from the Global Address List or shows it again. Has no effect on a group synchronised from on-premises Active Directory.</td><td>true</td></tr><tr><td>Set Group Visibility</td><td>Sets the group's visibility to Public, so anyone can see its content and join, or Private, so membership is controlled by the owners. Only offered for Microsoft 365 groups; in a mixed selection, only the Microsoft 365 groups are changed.</td><td>true</td></tr><tr><td>Only allow messages from people inside the organisation</td><td>Requires sender authentication, so the group only accepts mail from within the tenant. Has no effect on a group synchronised from on-premises Active Directory.</td><td>true</td></tr><tr><td>Allow messages from people inside and outside the organisation</td><td>Drops the sender authentication requirement, so the group accepts mail from external senders as well. Has no effect on a group synchronised from on-premises Active Directory.</td><td>true</td></tr><tr><td>Set Source of Authority</td><td>Switches the group between Cloud Managed and On-Premises Managed. Greyed out for cloud-native groups that have never been synchronised, and a move back to on-premises takes until the next sync cycle to appear.</td><td>true</td></tr><tr><td>Create template based on group</td><td>Creates a reusable group template from this group, copying its name, description, type, membership rule, alias and external sender setting.</td><td>true</td></tr><tr><td>Create Team from Group</td><td>Turns the group into a Microsoft Teams team, with the member, messaging and fun settings set in the dialog. Greyed out for anything other than a Microsoft 365 group.</td><td>true</td></tr><tr><td>Delete Group</td><td>Deletes the group.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
A group has to be at least fifteen minutes old before **Create Team from Group** will work, as Microsoft needs the group to have finished provisioning first.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
