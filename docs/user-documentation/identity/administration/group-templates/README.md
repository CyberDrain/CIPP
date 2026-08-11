# Group Templates

Group templates hold the settings for a group so the same group can be created repeatedly, in one tenant or across many. A template records the group's name, description, type and the settings that apply to that type, and is then applied from the deploy page. Templates are stored in CIPP rather than in a tenant, so the list is the same whichever tenant is selected.

## Action Buttons

{% content-ref url="add.md" %}
[add.md](add.md)
{% endcontent-ref %}

{% content-ref url="deploy.md" %}
[deploy.md](deploy.md)
{% endcontent-ref %}

## Table Details

| Column       | Description                                                                                                                                                                                                               |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name | The name the group is given when the template is applied.                                                                                                                                                                 |
| Description  | The description the group is given when the template is applied.                                                                                                                                                          |
| Group Type   | The kind of group the template creates, shown as its stored value: `m365`, `generic` for a security group, `security` for a mail-enabled security group, `distribution`, `dynamic`, `dynamicDistribution` or `azureRole`. |
| GUID         | The template's unique identifier in CIPP, used when the template is referenced elsewhere.                                                                                                                                 |

Everything else the template holds is shown in the Extended Info flyout, including the membership rule, the mail nickname, any licenses and aliases, whether external senders are allowed, whether the group is hidden from the Global Address List, and where the template came from.

{% hint style="info" %}
The Group Type column shows the stored value rather than the friendly name used on the Add Group Template page, so a plain security group reads as `generic` while a mail-enabled security group reads as `security`. Templates saved by older CIPP versions are normalised to these values when the list is built, so an older template still reports a recognisable type.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Template</td><td>Opens the <a data-mention href="edit.md">edit.md</a> page for the selected template.</td><td>false</td></tr><tr><td>Save to GitHub</td><td>Uploads the template to one of your GitHub repositories, prompting for the repository and a commit message. Only repositories you have write access to are offered. Greyed out unless the GitHub integration is enabled.</td><td>true</td></tr><tr><td>Delete Template</td><td>Deletes the template from CIPP. Groups already created from it are unaffected.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
