# Group Templates

Group templates hold the settings for a group so the same group can be created repeatedly, in one tenant or across many. A template records the group's name, description, type and the settings that apply to that type, and is then applied from the Deploy Group Template drawer on this page or the Groups page. Templates are stored in CIPP rather than in a tenant, so the list is the same whichever tenant is selected.

## Action Buttons

{% content-ref url="add.md" %}
[add.md](add.md)
{% endcontent-ref %}

<details>

<summary>Deploy Group Template</summary>

Opens a drawer that applies a saved group template to one or more tenants, creating the same group in each. The same drawer is available from the [README.md](../groups/README.md "mention") page. The values a template supplies can be adjusted for this deployment without changing the stored template.

Choose the tenants the group should be created in under **Select Tenants**. Several can be selected, and the group is created separately in each. There is no All Tenants option here, so the tenants have to be picked individually.

**Choose a Template** lists the saved templates by name and group type. Selecting one fills in the fields below, which can then be edited for this deployment. A template is not required: the fields can be completed by hand instead.

| Field                                              | Description                                                                                                                                                                                   |
| -------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Group Type                                         | The kind of group to create: Dynamic Group, Security Group, Distribution Group, Azure Role Group or Mail Enabled Security Group. Required, and it decides which of the settings below appear. |
| Group Display Name                                 | The name the group is created with. Required.                                                                                                                                                 |
| Group Description                                  | A description for the group.                                                                                                                                                                  |
| Group Username                                     | The mail nickname the group's email address is built from.                                                                                                                                    |
| Allow external emails to the group                 | Allows senders outside the organisation to email the group. Shown for a Distribution Group.                                                                                                   |
| Membership Rules                                   | The rule that decides membership. Shown for a Dynamic Group, and required.                                                                                                                    |
| Email Aliases                                      | Additional email addresses, one per line. Shown for a Distribution Group or Mail Enabled Security Group.                                                                                      |
| Hide this group from the Global Address List (GAL) | Hides the group from address lists. Shown for a Distribution Group or Mail Enabled Security Group.                                                                                            |

**Deploy Template** stays disabled until a tenant, a group type and a display name are set. The group is created in every selected tenant and the result is shown in the drawer, which can then be used again for another deployment.

{% hint style="info" %}
Any of the fields above accepts a variable, written as `%variablename%`, which is replaced with each target tenant's value as the group is created. `%tenantfilter%` gives the tenant's default domain, as in `postmaster@%tenantfilter%`, and `%tenantname%` gives the tenant's name, so one deployment can give every tenant a correctly named group. Values for your own variables are set for every tenant in [global-variables.md](../../../tenant/administration/tenants/global-variables.md "mention"), or for one tenant in the Custom Variables box on [edit.md](../../../tenant/manage/edit.md "mention"), where the tenant's own value wins.
{% endhint %}

{% hint style="info" %}
Licences held on a template are carried into the deployment even though the drawer does not display them, so a Security Group template with group-based licensing attached still assigns those licences. To see or change which licences a template holds, edit the template itself.
{% endhint %}

{% hint style="warning" %}
The Group Type list here does not include Microsoft 365 Group, so a Microsoft 365 template cannot be deployed from this drawer. Selecting one leaves the group type unset and Deploy Template stays disabled. Create Microsoft 365 groups from the [add.md](../groups/add.md "mention") page in the meantime.
{% endhint %}

</details>

## Table Details

| Column       | Description                                                                                                                                                                                                               |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name | The name the group is given when the template is applied.                                                                                                                                                                 |
| Description  | The description the group is given when the template is applied.                                                                                                                                                          |
| Group Type   | The kind of group the template creates, shown as its stored value: `m365`, `generic` for a security group, `security` for a mail-enabled security group, `distribution`, `dynamic`, `dynamicDistribution` or `azureRole`. |
| GUID         | The template's unique identifier in CIPP, used when the template is referenced elsewhere.                                                                                                                                 |

Everything else the template holds is shown in the Extended Info flyout, including the membership rule, the mail nickname, any licences and aliases, whether external senders are allowed, whether the group is hidden from the Global Address List, and where the template came from.

{% hint style="info" %}
The Group Type column shows the stored value rather than the friendly name used on the Add Group Template page, so a plain security group reads as `generic` while a mail-enabled security group reads as `security`. Templates saved by older CIPP versions are normalised to these values when the list is built, so an older template still reports a recognisable type.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Template</td><td>Opens the <a data-mention href="edit.md">edit.md</a> page for the selected template.</td><td>false</td></tr><tr><td>Save to GitHub</td><td>Uploads the template to one of your GitHub repositories, prompting for the repository and a commit message. Only repositories you have write access to are offered. Greyed out unless the GitHub integration is enabled.</td><td>true</td></tr><tr><td>Delete Template</td><td>Deletes the template from CIPP. Groups already created from it are unaffected.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
