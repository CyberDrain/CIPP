# CA Templates

This page lists the Conditional Access templates available in your CIPP instance. A template is a saved policy definition that can be deployed to any tenant, added to a standard, or shared through a GitHub repository.&#x20;

## Action Buttons

{% content-ref url="create-ca-template.md" %}
[create-ca-template.md](create-ca-template.md)
{% endcontent-ref %}

<details>

<summary>Browse Catalog</summary>

Opens the Browse Conditional Access Catalog drawer, for importing templates from elsewhere. The toggle at the top selects the source: **Community Catalog** browses published template repositories, while **From a Tenant** lets you pick one of your tenants, search its existing Conditional Access policies, and import one as a template. Either source lets you preview a policy's full JSON before importing.

</details>

<details>

<summary>View Logs</summary>

Opens the Conditional Access entries from the CIPP logs.

</details>

### Browse Catalog

The drawer offers two sources, chosen with the toggle at the top.

| Source            | Description                                                                                                |
| ----------------- | ---------------------------------------------------------------------------------------------------------- |
| Community Catalog | Browse published template repositories and import any Conditional Access templates they contain.           |
| From a Tenant     | Select one of your tenants, search its existing Conditional Access policies, and import one as a template. |

Either source lets you preview a policy's full JSON before importing. Imported templates appear in the table immediately.

## Table Details

| Column       | Description                                                                         |
| ------------ | ----------------------------------------------------------------------------------- |
| Display Name | The name of the template, taken from the policy it was built from.                  |
| Synced From  | The tenant or community repository a template library copies the template from.     |
| Package      | The package tag assigned to the template, used to group related templates together. |
| GUID         | The unique identifier CIPP uses for the template.                                   |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Deploy Template</td><td>Opens the Deploy Conditional Access Policy drawer with this template already selected, so you can choose a target tenant and deployment options.</td><td>true</td></tr><tr><td>Edit Template</td><td>Opens <a data-mention href="edit.md">edit.md</a> for editing. Greyed out for templates synced from a community repository, which are kept in step with the repository rather than edited in CIPP. Use <strong>Clone Template</strong> to get a copy you can edit.</td><td>false</td></tr><tr><td>Clone Template</td><td>Creates a copy of the template that is no longer synced with a template library, so it can be edited freely and is never overwritten by a sync. The copy is not placed in any package.</td><td>true</td></tr><tr><td>Add to package</td><td>Assigns a package tag to the selected template or templates. Pick an existing package from the dropdown, or type a new package name.</td><td>true</td></tr><tr><td>Remove from package</td><td>Clears the package tag from the selected template or templates.</td><td>true</td></tr><tr><td>Save to GitHub</td><td>Commits the template to a repository you have write access to, with a commit message of your choosing. Only shown when the GitHub integration is enabled.</td><td>true</td></tr><tr><td>Delete Template</td><td>Deletes the template from CIPP. Policies already deployed from it are not affected.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
Assigning the same package name to several templates groups them, which is useful for keeping a baseline set together when deploying to a new tenant. Packages are viewed, renamed and deleted from [template-packages.md](../../../tools/template-packages.md "mention").
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
