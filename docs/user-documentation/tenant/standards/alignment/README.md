# Standards & Drift Alignment

{% hint style="warning" %}
## **Understanding Standards**

This page is a reference to the features of the Standard & Drift Alignment page in CIPP. To better understand Standards and Drift, please see the main page for [..](../ "mention").
{% endhint %}

This page gives you a snapshot of how your tenants measure up against your Standards and Drift templates. The same underlying data is presented three ways, and you switch between them with the toggle at the top of the table. Each view carries its own columns, filters, and actions.

| View         | Use it to                                                                      |
| ------------ | ------------------------------------------------------------------------------ |
| Summary      | See one row per tenant and template pairing, for an overall alignment picture. |
| Per Standard | Drill into individual standards, one row per tenant per standard.              |
| By Standard  | Aggregate across tenants, to see how a single standard is faring estate-wide.  |

## Summary View

One row per tenant and template pairing, showing how closely that tenant matches that template overall.

### Filters

| Filter            | Shows                                                     |
| ----------------- | --------------------------------------------------------- |
| Drift Templates   | Shows only rows for templates that are Drift Standards.   |
| Classic Templates | Shows only rows for templates that are Classic Standards. |

### Table Details

| Column                     | Description                                                                                                                                                    |
| -------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant                     | The name of the tenant.                                                                                                                                        |
| Standard Name              | The name of the template the tenant is being aligned to.                                                                                                       |
| Standard Type              | Whether the template is a Classic Standard or a Drift Standard.                                                                                                |
| Alignment Score            | The percentage of standards in the template that the tenant is aligned with.                                                                                   |
| License Missing Percentage | The percentage of standards in the template that the tenant is not licensed for. 0% means the tenant holds the licences needed for everything in the template. |
| Combined Alignment Score   | Alignment reweighted to discount standards the tenant is not licensed for, so unlicensed settings do not count against the tenant.                             |
| Pending Deviations Count   | For drift templates, the number of detected deviations awaiting a decision.                                                                                    |
| Denied Deviations Count    | For drift templates, the number of deviations that have been denied.                                                                                           |

Filters are available for **Drift Templates** and **Classic Templates**.

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Tenant Report</td><td>Opens the <a data-mention href="../../manage/applied-standards.md">applied-standards.md</a> for this tenant and template.</td><td>false</td></tr><tr><td>Edit Template</td><td>Opens the template for editing.</td><td>false</td></tr><tr><td>Manage Drift</td><td>Opens the <a data-mention href="../../manage/drift.md">drift.md</a> page for this tenant and template. Only shown on drift templates.</td><td>false</td></tr><tr><td>Remove Drift Customization</td><td>Removes all global and client level overrides and resets the tenant to the template settings. Only shown on drift templates. This regenerates alerts for the items that had drifted.</td><td>true</td></tr></tbody></table>

## Per Standard View

One row per tenant per standard, so you can filter down to a single standard and see exactly which tenants are failing it.

### Filters

| Filter             | Shows                                                                                                              |
| ------------------ | ----------------------------------------------------------------------------------------------------------------- |
| Non-Compliant      | Shows only rows where the tenant does not match the standard.                                                     |
| Compliant          | Shows only rows where the tenant matches the standard.                                                            |
| Accepted Deviation | Shows only rows where the tenant differs from the standard but the difference has been reviewed and accepted.     |
| Customer Specific  | Shows only rows where the tenant has a deliberate customer-specific value in place of the template's.             |
| License Missing    | Shows only rows where the tenant is not licensed for the setting, so the standard was skipped rather than failed. |

### Table Details

| Column                 | Description                                                     |
| ---------------------- | --------------------------------------------------------------- |
| Tenant                 | The name of the tenant.                                         |
| Compliance Status      | The result for this standard on this tenant. See below.         |
| Standard Name          | The name of the standard being evaluated.                       |
| Template Name          | The template containing the standard.                           |
| Standard Type          | Whether the template is a Classic Standard or a Drift Standard. |
| Latest Data Collection | How long ago the data behind this result was collected.         |

#### Compliance Status

| Status             | Description                                                                                 |
| ------------------ | ------------------------------------------------------------------------------------------- |
| Compliant          | The tenant matches the standard.                                                            |
| Non-Compliant      | The tenant does not match the standard.                                                     |
| Accepted Deviation | The tenant differs from the standard, but the difference has been reviewed and accepted.    |
| Customer Specific  | The tenant has a deliberate client-specific value set in place of the template's.           |
| License Missing    | The tenant is not licensed for the setting, so the standard was skipped rather than failed. |
| Reporting Disabled | The standard is applied without Report enabled, so there is no result to compare.           |

Filters are available for **Non-Compliant**, **Compliant**, **Accepted Deviation**, **Customer Specific**, and **License Missing**.

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>View Tenant Report</td><td>Opens the <a data-mention href="../../manage/applied-standards.md">applied-standards.md</a> for this tenant and template.</td><td>false</td></tr><tr><td>Edit Template</td><td>Opens the template for editing.</td><td>false</td></tr><tr><td>Manage Drift</td><td>Opens the <a data-mention href="../../manage/drift.md">drift.md</a> page for this tenant and template. Only shown on drift templates.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

## By Standard View

One row per standard, aggregated across every tenant it applies to. Use this to find the standards that are failing widely rather than the tenants that are failing.

### Filters

| Filter             | Shows                                                                                                                                              |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| Fully Compliant    | Shows only standards where every applicable tenant is aligned, whether compliant, on an accepted deviation, or set to a customer-specific value. |
| Has Non-Compliant  | Shows only standards where at least one tenant is non-compliant.                                                                                 |
| License Missing    | Shows only standards where at least one tenant is missing the licence needed for it.                                                             |
| Accepted Deviation | Shows only standards where at least one tenant has an accepted deviation from it.                                                                |

### Table Details

| Column                     | Description                                                                                                  |
| -------------------------- | ------------------------------------------------------------------------------------------------------------ |
| Standard Name              | The name of the standard being evaluated.                                                                    |
| Category                   | The category the standard belongs to.                                                                        |
| Standard Type              | The template type or types the standard is applied through across your tenants.                              |
| Total Tenants              | The number of tenants the standard applies to.                                                               |
| Tenants                    | The tenants the standard applies to.                                                                         |
| Compliance Percentage      | The percentage of those tenants that are in compliance with the standard.                                    |
| License Missing Percentage | The percentage of those tenants that are not licensed for the standard.                                      |
| Aligned Count              | The number of tenants counted as aligned, which covers Compliant, Accepted Deviation, and Customer Specific. |
| Compliant Count            | The number of tenants that are compliant.                                                                    |
| Non Compliant Count        | The number of tenants that are non-compliant.                                                                |
| License Missing Count      | The number of tenants that lack the licensing for the standard.                                              |
| Accepted Deviation Count   | The number of tenants with an accepted deviation from the standard.                                          |

Filters are available for **Fully Compliant**, **Has Non-Compliant**, **License Missing**, and **Accepted Deviation**.

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

Selecting a row opens the Standard Tenant Summary flyout, which lists the tenants the standard applies to and can be filtered to show only the compliant or only the non-compliant ones.

## Known Issues

* There is currently a limitation with Conditional Access classic standards due to the complexity of comparing the standard settings against the Conditional Access response object. We hope to resolve this in a future update.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
