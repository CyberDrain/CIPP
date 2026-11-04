# Enrollment Restriction Templates

Lists the enrollment restriction templates saved in your CIPP instance. A template holds a restriction's platform settings, priority, and assignment, and can be deployed to any tenant or kept in place by a baseline.

## Action Buttons

{% content-ref url="add.md" %}
[add.md](add.md)
{% endcontent-ref %}

<details>

<summary>Deploy Template</summary>

Opens the Deploy Enrollment Restriction Template drawer. In each selected tenant, a restriction with the template's name on the same platform is updated, or created if there is none. A summary of what the deployment does appears once a template is chosen, followed by the template's full settings.

| Field                                    | Description                                                                                                                                                                                                                                                                                                                                       |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Select Tenants                           | The tenants the template is deployed to. At least one is required.                                                                                                                                                                                                                                                                                |
| Choose a template                        | The template to deploy. Already selected when the drawer is opened from a row.                                                                                                                                                                                                                                                                    |
| How should groups and users be handled?  | **Leave the groups and users as is** keeps an existing restriction's assignment, and creates a new restriction without one. **Replace by display name** assigns the template's groups, looked up by name in each tenant. **Apply to all users** assigns the restriction to every user, whatever the template says.                                    |
| Create groups if they do not exist       | Only available with **Replace by display name**. Creates any group the template names that a tenant does not have, from the group template of the same name where there is one, or as a security group otherwise. Names containing a wildcard are not created. Where a group cannot be created, the restriction is not written to that tenant and the result says why. |

The template's priority only applies when a restriction is created. An existing restriction keeps its position.

</details>

## Table Details

| Column            | Description                                                                                       |
| ----------------- | ------------------------------------------------------------------------------------------------- |
| Platform Label    | The platform the template's restriction applies to.                                               |
| Display Name      | The name of the restriction the template creates or updates.                                      |
| Description       | The template's description.                                                                       |
| Priority          | The position a new restriction is placed at. Blank places it below each tenant's existing restrictions. |
| Policy Assignment | **All Licensed Users**, the group names the template assigns, or **Not assigned**.                |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Deploy Template</td><td>Opens the Deploy Enrollment Restriction Template drawer with this template already selected.</td><td>true</td></tr><tr><td>Edit Template</td><td>Opens <a data-mention href="edit.md">edit.md</a> for editing.</td><td>false</td></tr><tr><td>Delete Template</td><td>Deletes the template from CIPP. Restrictions already deployed from it are not changed.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="success" %}
To keep a template deployed across many tenants, add the **Enrollment Restriction Template** baseline. It checks each tenant's restriction against the template and corrects any drift.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
