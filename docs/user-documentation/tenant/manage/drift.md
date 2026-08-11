# Manage Drift

This page and the other tabs are a way for you to manage your tenants and their drift away from the desired settings in your Drift Management template.

## Manage Drift Overview

{% @storylane/embed subdomain="app" url="https://app.storylane.io/share/cqb21ohc9fgp" linkValue="cqb21ohc9fgp" %}

The Manage Drift page shows how a tenant's live configuration compares with the drift template applied to it, and lets you decide what to do about each difference. A deviation is a setting that no longer matches the template. For each one you can accept it, leaving the tenant as it is; accept it as specific to that customer; or deny it, either by deleting the offending policy or by remediating the tenant back to the template. A drift template and a tenant must both be selected before any results are shown.

## Page Actions

| Action           | Description                                                                                                                                                  |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Refresh Data     | Reloads the drift results for the selected tenant and template.                                                                                              |
| Generate Report  | Produces an executive report of the current drift results as a PDF.                                                                                          |
| Run Standard Now | Forces an immediate run of the standard rather than waiting for its schedule. You choose which tenant to run against. Available once a template is selected. |

## Breakdown

A summary panel counts the deviations by how they have been handled.

| Figure               | Description                                                                           |
| -------------------- | ------------------------------------------------------------------------------------- |
| Aligned              | Standards where the tenant matches the template.                                      |
| Current              | Deviations that have not yet been accepted or denied.                                 |
| Accepted             | Deviations that have been accepted and left in place.                                 |
| Customer Specific    | Deviations accepted as specific to this customer.                                     |
| Denied               | Deviations that have been denied, whether by deletion or remediation.                 |
| Skipped (No License) | Standards that could not be evaluated because the tenant lacks the required licenses. |
| Total                | The total number of standards evaluated.                                              |

## Filters

| Control               | Description                                                                                                  |
| --------------------- | ------------------------------------------------------------------------------------------------------------ |
| Select Drift Template | The drift template to evaluate the tenant against.                                                           |
| Search deviations     | Narrows the list to deviations matching the text entered.                                                    |
| Status                | Restricts the list to All Deviations, Current Deviations, Accepted, Customer Specific, Denied, or Compliant. |
| Sort by               | Orders the results by Name, Status, or Category.                                                             |

## Deviations

Results are presented as cards grouped into sections, each showing what the template expects and what the tenant currently has.

| Section                                 | Contains                                                                              |
| --------------------------------------- | ------------------------------------------------------------------------------------- |
| New Deviations                          | Differences that have not yet been actioned. These are the items awaiting a decision. |
| Accepted Deviations                     | Differences that have been accepted and will remain in place.                         |
| Accepted Deviations - Customer Specific | Differences accepted as specific to this customer.                                    |
| Denied Deviations                       | Differences that have been denied and either removed or remediated.                   |
| Compliant Standards                     | Standards where the tenant already matches the template.                              |
| Skipped - No License Available          | Standards that could not be evaluated because the tenant lacks the required licenses. |

### Actions on a Deviation

Each card carries an **Actions** menu. Which options appear depends on what the deviation is: deletion only applies where a policy exists in the tenant but not in the template, and remediation only applies where the policy exists in the template.

| Action                                            | Description                                                                                       |
| ------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Accept Deviation - Customer Specific              | Accepts the difference and records it as specific to this customer, leaving the tenant unchanged. |
| Accept Deviation                                  | Accepts the difference and leaves the tenant unchanged.                                           |
| Deny Deviation - Delete Policy                    | Denies the difference and deletes the policy from the tenant.                                     |
| Deny Deviation - Remediate to align with template | Denies the difference and changes the tenant back to match the template.                          |

Cards for Intune template standards also carry a **Compare** button, described below.

### Bulk Actions

Selecting one or more deviations reveals a **Bulk Actions** button showing how many are selected. The same accept and deny options are offered, applied to every selected deviation at once. The delete and remediate options only appear when all of the selected deviations support them.

An additional **Remove Drift Customization** option clears the recorded decisions, returning the selected deviations to an unactioned state.

### Confirming a Decision

Accepting or denying a deviation opens a confirmation dialog. A **Reason for change** must be entered and is mandatory, so that decisions carry an audit trail. When denying with remediation, a **Permanently deny - Reset every 12 hours** option is also offered, which re-applies the remediation on a recurring basis rather than only once.

## Comparing Against the Baseline

For deviations that come from an Intune template standard, a **Compare** button opens a comparison of the template baseline against the policy as it exists in the tenant.

| Element             | Description                                                                                                                              |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Not deployed notice | Shown where the policy does not exist in the tenant at all, naming the policy that is missing.                                           |
| Summary             | States whether the two are identical, or how many differences were found.                                                                |
| Differences table   | Lists each differing property with its Baseline and Tenant values, and whether the values differ or the setting exists on only one side. |
| Full settings       | The complete configuration of both the baseline and the tenant policy, for reviewing settings the comparison treated as matching.        |

{% include "../../../../.gitbook/includes/feature-request.md" %}
