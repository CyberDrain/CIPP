# Policy Templates

Lists the Intune policy templates saved in CIPP, which are the templates the **Deploy Policy** button on the policy pages draws from. Templates can be imported from a community repository, captured from an existing tenant, or created by saving a policy from one of the policy list pages. Filter buttons narrow the list to Synced Templates or Custom Templates.

## Action Buttons

<details>

<summary>Browse Catalog</summary>

Opens a drawer for adding templates to CIPP, with two sources to choose between.

**Community Catalog** is the template catalog described in [community-repos](../../../tools/community-repos/ "mention"), narrowed to Intune templates. Templates can be previewed and imported the same way as on that page.

**From a Tenant** captures an existing policy from one of your tenants as a template. Select a tenant, then search its policies by name or description and import the one you want.

</details>

{% @storylane/embed subdomain="app" url="https://app.storylane.io/share/939rpjvy23oy" linkValue="939rpjvy23oy" %}

## Filters

| Filter           | Shows                                                      |
| ---------------- | ---------------------------------------------------------- |
| Synced Templates | Templates that are still linked to a community repository. |
| Custom Templates | Templates that are not linked to a community repository.   |

## Table Details

| Column       | Description                                                                                                                                                                     |
| ------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name | The name of the template.                                                                                                                                                       |
| Is Synced    | Whether the template came from a community repository and is still linked to it. A template that has been edited or cloned is no longer linked and shows as not synced.         |
| Package      | The package the template has been tagged with, where one has been assigned. Packages let a standards template pull in a set of templates by tag rather than by naming each one. |
| Description  | The description recorded against the template.                                                                                                                                  |
| Type         | The template type, for example Catalog, Device, Admin, AppProtection or deviceCompliancePolicies. This determines how the policy is written when deployed.                      |
| Usage        | The standards templates that use this template, and whether each one references it directly or picks it up through its package tag.                                             |

{% hint style="info" %}
Selecting a row opens a flyout listing the standards templates the template is used in, each linking through to that template, followed by the template's own configuration. This is worth checking before deleting a template, since a template in use by a standard will stop that standard applying.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Template</td><td>Opens the template for editing in <a data-mention href="edit.md">edit.md</a>. Only offered for templates that are not synced to a community repository.</td><td>false</td></tr><tr><td>Edit Template Name and Description</td><td>Changes the template's name and description. Applying this disconnects the template from the community repository it came from, so it will no longer receive updates.</td><td>true</td></tr><tr><td>Clone Template</td><td>Creates a copy of the template in CIPP. The copy is not linked to a community repository, so it can be edited freely.</td><td>true</td></tr><tr><td>Add to package</td><td>Tags the template with a package name, so that standards templates referencing that package pick it up. Enter the package name to assign.</td><td>true</td></tr><tr><td>Remove from package</td><td>Removes the package tag from the template.</td><td>true</td></tr><tr><td>Save to GitHub</td><td>Uploads the template to one of your GitHub repositories, prompting for the repository and a commit message. Only repositories you have write access to are offered. Hidden unless the GitHub integration is enabled.</td><td>true</td></tr><tr><td>Delete Template</td><td>Deletes the template from CIPP. Policies already deployed from it are unaffected.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
