# Policy Templates

Lists the Intune policy templates saved in CIPP, which are the templates the **Deploy Policy** button on the policy pages draws from. Templates can be imported from a community repository, captured from an existing tenant, or created by saving a policy from one of the policy list pages. Filter buttons narrow the list to Synced Templates or Custom Templates.

## Action Buttons

<details>

<summary>Create New Template</summary>

Opens [add.md](add.md "mention"), where you build a Settings Catalog template from scratch by searching for the settings you want, optionally starting from an endpoint security profile.

</details>

<details>

<summary>Browse Catalog</summary>

Opens a drawer for adding templates to CIPP, with two sources to choose between.

**Community Catalog** is the template catalogue described in [community-repos](../../../tools/community-repos/ "mention"), narrowed to Intune templates. Templates can be previewed and imported the same way as on that page.

**From a Tenant** captures an existing policy from one of your tenants as a template. Select a tenant, then search its policies by name or description and import the one you want.

To refresh a template after the policy changed in the tenant, turn on **Replace the template with the same name**: the template is updated in place, keeping its package, instead of a second copy being added. Turn on **Keep the variables added to that template** as well to keep any `%variables%` you put in it: each setting that held a variable keeps it, and every other setting takes the tenant's current value. If a setting holding a variable is gone from the policy, the result lists that variable. When two templates have the same name, nothing is saved; rename one first. The same options appear on **Create template based on policy** on the policy lists.

</details>

{% @storylane/embed subdomain="app" url="https://app.storylane.io/share/939rpjvy23oy" linkValue="939rpjvy23oy" %}

## Filters

| Filter           | Shows                                                      |
| ---------------- | ---------------------------------------------------------- |
| Synced Templates | Templates a template library keeps in step with a community repository. |
| Custom Templates | Templates that are not kept in step, including ones imported once from the Template Catalog. |

## Table Details

| Column       | Description                                                                                                                                                                                                                                                                                               |
| ------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name | The name of the template.                                                                                                                                                                                                                                                                                 |
| Is Synced    | Whether a template library keeps the template in step with a community repository. A template imported once from the Template Catalog, or one that has been edited or cloned, shows as not synced.                                                                                                                                |
| Synced From  | The repository the template was imported from, shown as owner and repository name. Empty for templates created or cloned in CIPP.                                                                                                                                                                         |
| Package      | The package the template has been tagged with, where one has been assigned. Packages let a standards template pull in a set of templates by tag rather than by naming each one.                                                                                                                           |
| Description  | The description recorded against the template.                                                                                                                                                                                                                                                            |
| Type         | The template type, for example Catalog, Device, Admin, AppProtection or deviceCompliancePolicies. This determines how the policy is written when deployed.                                                                                                                                                |
| Usage        | The baselines and standards templates that use this template, one chip each. A chip names the baseline or standards template, the baseline stage where there is one, whether it remediates or only reports, and the package where the template is picked up through its package tag rather than directly. |

{% hint style="info" %}
The **More Info** flyout opens with a **Used in Baselines and Standards Templates** table listing everything that uses the template, followed by the template's own configuration. Each row links through to the baseline or standards template, and shows its **Type**, the baseline **Stage**, whether it is set to **Remediate** or **Report only**, and whether it includes the template directly or through a package. This is worth checking before deleting a template, since a template in use by a baseline or standard will stop it applying.
{% endhint %}

{% hint style="info" %}
Packages are viewed, renamed and deleted from [template-packages.md](../../../tools/template-packages.md "mention").
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Template</td><td>Opens the template for editing in <a data-mention href="edit.md">edit.md</a>. Only offered for templates that are not synced to a community repository.</td><td>false</td></tr><tr><td>Validate Template</td><td>Checks the template for problems that would stop it deploying, and lists every problem found. Nothing is saved or deployed. Optionally pick a tenant to also check the template's replacement variables and whether the tenant offers each setting.</td><td>true</td></tr><tr><td>Edit Template Name and Description</td><td>Changes the template's name and description. Applying this to a synced template disconnects it from the community repository it came from, so it will no longer receive updates. A template imported once from the Template Catalog keeps its link, so the catalog still shows it as imported.</td><td>true</td></tr><tr><td>Clone Template</td><td>Creates a copy of the template in CIPP. The copy is not linked to a community repository, so it can be edited freely.</td><td>true</td></tr><tr><td>Add to package</td><td>Tags the template with a package name, so that standards templates referencing that package pick it up. Pick an existing package from the dropdown, or type a new package name.</td><td>true</td></tr><tr><td>Remove from package</td><td>Removes the package tag from the template.</td><td>true</td></tr><tr><td>Save to GitHub</td><td>Uploads the template to one of your GitHub repositories, prompting for the repository and a commit message. Only repositories you have write access to are offered. Hidden unless the GitHub integration is enabled.</td><td>true</td></tr><tr><td>Delete Template</td><td>Deletes the template from CIPP. Policies already deployed from it are unaffected.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
