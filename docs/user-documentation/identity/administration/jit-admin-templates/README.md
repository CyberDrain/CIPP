# JIT Admin Templates

JIT Admin templates hold the settings for a just-in-time admin grant so the same elevation can be requested repeatedly without rebuilding it each time. A template records the roles, duration, expiry behavior and notification choices, and is then selected on the add.md page.

## Action Buttons

<details>

<summary>Add JIT Admin Template</summary>

Links to [add-jit-admin-template.md](add-jit-admin-template.md "mention")

</details>

## Table Details

| Column                        | Description                                                                                                    |
| ----------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Template Name                 | The name given to the template.                                                                                |
| Default For Tenant            | Whether this template is applied automatically when the JIT admin form is opened for the tenant it belongs to. |
| Tenant                        | The tenant the template belongs to, or All Tenants for one available everywhere.                               |
| Default Duration - Label      | How long the elevation lasts, which sets the end date on the form.                                             |
| Default Roles                 | The Entra ID directory roles the template assigns.                                                             |
| Generate TAP By Default       | Whether a Temporary Access Pass is issued with the grant.                                                      |
| Default Expire Action - Label | What happens to the account when the elevation ends.                                                           |
| Default Notification Actions  | Which channels are notified when the grant is created.                                                         |
| Reason Template               | The reason text the template pre-fills, which the requester can then adjust.                                   |

{% hint style="info" %}
This list is scoped to the tenant selected in the tenant selector, and shows that tenant's own templates alongside any created for All Tenants. Choosing All Tenants narrows the list to the All Tenants templates only, so a template created for one customer will not appear while a different customer is selected.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Template</td><td>Opens the selected template for editing in <a data-mention href="edit-jit-admin-template.md">edit-jit-admin-template.md</a>.</td><td>false</td></tr><tr><td>Save to GitHub</td><td>Uploads the template to one of your GitHub repositories, prompting for the repository and a commit message. Only repositories you have write access to are offered. Greyed out unless the GitHub integration is enabled.</td><td>true</td></tr><tr><td>Delete Template</td><td>Deletes the template from CIPP. Grants already created from it are unaffected and still expire as scheduled.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="warning" %}
Only one template should be marked as the default for a given tenant. Where both a tenant-specific default and an All Tenants default exist, the tenant-specific one is applied.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
