# Templates

{% hint style="warning" %}
## **Understanding Standards**

This page is a reference to the features of the Standards Templates page in CIPP. To better understand Standards and Drift, please see the main page for ...
{% endhint %}

This page lists every Standards and Drift template you have built. A template is a named set of standards together with the tenants it applies to, and it is the unit CIPP schedules, runs, and reports against.

For a list of the standards you can configure inside a template, see [available-standards.md](available-standards.md "mention").

## Action Buttons

`Add Template` and `Create Drift Template` will open [template.md](../../template.md "mention") with the settings available for the respective template type.

<details>

<summary>Browse Catalog</summary>

Opens the policy catalog, where you can import a prebuilt standards template rather than assembling one yourself.

</details>

{% hint style="info" %}
If you are upgrading from a version of CIPP that predates templates, a **Convert Legacy Standards** prompt appears above the table whenever legacy standards are detected. Converting creates a new template for each standard you had, with the schedule disabled. Check each new template is correct before re-enabling its schedule.
{% endhint %}

## Table Details

| Column           | Description                                                                                      |
| ---------------- | ------------------------------------------------------------------------------------------------ |
| Template Name    | The name you set when creating the template.                                                     |
| Type             | Whether this is a Standards template or a Drift template.                                        |
| Tenant           | The tenant, tenants, or tenant groups the template applies to.                                   |
| Excluded Tenants | Tenants excluded from an All Tenants template.                                                   |
| Updated At       | How long ago the template was last changed.                                                      |
| Updated By       | The CIPP user who last changed the template.                                                     |
| Run Manually     | Whether the template is set to run only on demand. Ticked means it will not run on the schedule. |
| Standards        | The standards contained in the template.                                                         |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Tenant Report</td><td>Opens the applied standards report, comparing the template against the settings discovered for the selected tenant.</td><td>false</td></tr><tr><td>Edit Template</td><td>Opens the template configuration page.</td><td>false</td></tr><tr><td>Clone &#x26; Edit Template</td><td>Copies the template and opens the copy for editing, so you can adjust it before saving it as a new template.</td><td>false</td></tr><tr><td>Create Drift Clone</td><td>Creates a new Drift template based on this template, so an existing Standards template can be reused for monitoring.</td><td>true</td></tr><tr><td>Run Template Now</td><td>Forces a run outside the schedule. You are asked which tenants to run against, and only tenants and groups assigned to the template are offered.</td><td>true</td></tr><tr><td>Set Schedule</td><td>Switches the template between running on the schedule and running manually only. Not available on Drift templates, which always run on the schedule.</td><td>true</td></tr><tr><td>Save to GitHub</td><td>Commits the template to a repository, with a commit message of your choosing. Only shown when the GitHub integration is enabled.</td><td>true</td></tr><tr><td>Delete Template</td><td>Deletes the template.</td><td>true</td></tr></tbody></table>

{% include "../../../../../../.gitbook/includes/feature-request.md" %}
