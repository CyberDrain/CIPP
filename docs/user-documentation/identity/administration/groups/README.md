---
description: Interact with Microsoft 365 groups.
---

# Groups

The Groups page lists every group in the tenant and is where group membership, mail behavior and lifecycle are managed. It covers the same ground as [Microsoft 365 admin center > Active teams and groups](https://admin.microsoft.com/#/groups), and extends it with actions that would otherwise need Exchange Online PowerShell.

## Action Buttons

<details>

<summary>Show Members</summary>

Adds a column listing the members of each group. You may need to select the column from the table's column selector as well.

Showing members and showing owners are mutually exclusive, because Graph accepts only one expansion per request, so turning one on turns the other off. Both buttons are hidden while the table is showing cached data.

</details>

<details>

<summary>Show Owners</summary>

Adds a column listing the owners of each group, under the same one-at-a-time restriction as Show Members.

</details>

{% content-ref url="add.md" %}
[add.md](add.md)
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
| Assigned Licenses            | Licenses assigned to the group for group-based licensing.                                                                                     |
| License Processing State     | How far Entra has got with applying group-based licenses to the members.                                                                      |
| Visibility                   | Whether the group is public or private.                                                                                                       |
| On Premises Sam Account Name | The account name the group carries when it is synchronised from on-premises Active Directory.                                                 |
| Membership Rule              | The rule that decides membership, for a dynamic group.                                                                                        |
| On Premises Sync Enabled     | Whether the group is synchronised from on-premises Active Directory.                                                                          |

Showing members or owners adds a further column listing them. In cached mode a **Cache Timestamp** column records when the cache was last refreshed, and a **Tenant** column is added when the tenant selector is set to All Tenants.

{% hint style="info" %}
Group Type is composed by CIPP rather than returned by Graph, which reports the same information across the `groupTypes`, `mailEnabled` and `securityEnabled` properties. A group is Microsoft 365 when its `groupTypes` include `Unified`, Mail-Enabled Security when it is both mail and security enabled, Security when it is security enabled alone, and a Distribution List when it is mail enabled alone. This matters when comparing against Graph output or the Entra portal, where no single equivalent field exists.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Group</td><td>Opens the <a data-mention href="group.md">group.md</a> page for the group, covering its membership, owners and settings.</td><td>false</td></tr><tr><td>Edit Group</td><td>Opens the <a data-mention href="edit.md">edit.md</a> page, where membership, owners and group settings can be changed.</td><td>false</td></tr><tr><td>Set Global Address List Visibility</td><td>Hides the group from the Global Address List or shows it again. Has no effect on a group synchronised from on-premises Active Directory.</td><td>true</td></tr><tr><td>Only allow messages from people inside the organization</td><td>Requires sender authentication, so the group only accepts mail from within the tenant. Has no effect on a group synchronised from on-premises Active Directory.</td><td>true</td></tr><tr><td>Allow messages from people inside and outside the organization</td><td>Drops the sender authentication requirement, so the group accepts mail from external senders as well. Has no effect on a group synchronised from on-premises Active Directory.</td><td>true</td></tr><tr><td>Set Source of Authority</td><td>Switches the group between Cloud Managed and On-Premises Managed. Greyed out for cloud-native groups that have never been synchronised, and a move back to on-premises takes until the next sync cycle to appear.</td><td>true</td></tr><tr><td>Create template based on group</td><td>Creates a reusable group template from this group, copying its name, description, type, membership rule, alias and external sender setting.</td><td>true</td></tr><tr><td>Create Team from Group</td><td>Turns the group into a Microsoft Teams team, with the member, messaging and fun settings set in the dialog. Greyed out for anything other than a Microsoft 365 group.</td><td>true</td></tr><tr><td>Delete Group</td><td>Deletes the group.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
A group has to be at least fifteen minutes old before **Create Team from Group** will work, as Microsoft needs the group to have finished provisioning first.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
