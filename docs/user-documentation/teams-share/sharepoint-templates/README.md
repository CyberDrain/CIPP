# SharePoint Templates

The SharePoint Templates page lists the saved SharePoint provisioning templates in CIPP. Each template defines one or more site templates, each provisioning a SharePoint site or a Microsoft Team, with its document libraries and, for a Team, any extra channels and folders. Templates can be deployed to tenants to provision sites and Teams in a consistent way. From here you can create, edit, copy, and delete templates, as well as deploy a template to a tenant.

## Action Buttons

{% content-ref url="add.md" %}
[add.md](add.md)
{% endcontent-ref %}

<details>

<summary>Deploy Template</summary>

Deploying pushes a saved template out to a tenant, provisioning the sites and Teams, document libraries, permissions, and Teams [channels](add.md#channels) and [folders](add.md#folders) it defines. Selecting **Deploy Template** opens a side panel.

| Field             | Description                                                                                                                                                                                       |
| ----------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Select Template   | The saved template you want to deploy. Required.                                                                                                                                                  |
| Select Tenant     | The tenant to deploy the template to. One tenant per deployment. Required.                                                                                                                        |
| Site / Team Owner | The user who will be set as the owner of every site or Team the template creates. The list shows the enabled, licensed users in the selected tenant, and clears if you change the tenant. Required. |

The **Deploy Template** button in the panel queues the deployment, and only becomes available once a template, a tenant, and an owner have been chosen. A **Deployment Progress** view then updates live for each site or Team, showing which step it has reached, such as applying permissions or creating a channel, library, or folder. If any of those steps fail, the site or Team is marked as failed with the reason, and its remaining steps still run. When it finishes, select **Deploy Again** to run another deployment, or **Close** to dismiss the panel.

</details>

## Table Details

| Column              | Description                                                                         |
| ------------------- | ----------------------------------------------------------------------------------- |
| Template Name       | The name given to the SharePoint template.                                          |
| Site Template Count | The number of site templates defined within this template.                          |
| Library Count       | The total number of document libraries across all of the template's site templates. |
| Updated By          | The user who last updated the template.                                             |
| Timestamp           | The date and time the template was last modified.                                   |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Template</td><td>Opens the selected template in the same editor as <a data-mention href="add.md">add.md</a> so you can change its settings. Greyed out unless you have SharePoint admin write access.</td><td>false</td></tr><tr><td>Copy Template</td><td>Opens the editor pre-filled from the selected template so you can save it as a new template under a different name. Greyed out unless you have SharePoint admin write access.</td><td>false</td></tr><tr><td>Delete Template</td><td>Permanently removes the selected template. Greyed out unless you have SharePoint admin write access.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
