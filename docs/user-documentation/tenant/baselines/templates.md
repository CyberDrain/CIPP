---
description: Create, import, run and manage the baselines applied to your tenants
---

# Manage Baselines

Every baseline you have created or imported is listed here, with the standards it carries, the tenants it is assigned to, and how far each tenant has progressed through its stages. This is where baselines are added, edited, run on demand, shared, and removed.

## Action Buttons

<details>

<summary>Add Baseline</summary>

Opens the [baseline editor](template.md) on a new, empty baseline.

</details>

<details>

<summary>Browse Catalog</summary>

Opens the baseline catalogue in a flyout, listing the ready-made baselines published in the community repositories you have connected. Importing one adds it to this list, where it can then be edited and assigned.

</details>

<details>

<summary>Migrate from Standards</summary>

Converts your classic Standards templates, drift templates included, into baselines. The originals are never modified, but while the Baselines feature is switched on the classic Standards and Drift pages and their scheduled runs stay turned off, so only one engine manages your tenants at a time.

The flyout previews every template it found and pre-selects the ones it can convert. Clear the tick against any you would rather leave behind, then use the **Migrate** button at the bottom.

| Field                                                                                                                      | Description                                                                                                                                                               |
| -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Import everything as report-only (recommended)                                                                             | Brings every standard across with automatic fixing switched off, so you can review the results before letting CIPP change anything. Re-enable it per standard afterwards. |
| Migrated drift templates should also alert on Intune and Conditional Access policies that were not created from a template | Adds detection of policies that exist in the tenant but were never deployed from a template, so they surface as deviations.                                               |

Tenant overrides cannot be prepared before migrating. Import as report-only, create the overrides you need from the [Alignment](alignment.md) page, then turn on automatic fixing.

Each template in the list carries a status.

| Status      | Meaning                                                                      |
| ----------- | ---------------------------------------------------------------------------- |
| Ready       | The template has not been migrated before and will be created as a baseline. |
| Will update | A baseline already exists for this template and will be brought up to date.  |
| Up to date  | An existing baseline already matches the template, so nothing is done.       |
| Skipped     | The template was not converted. The row explains why.                        |
| Migrated    | The template was created as a new baseline during this run.                  |
| Updated     | An existing baseline was brought up to date during this run.                 |
| Failed      | The conversion did not complete. The row explains why.                       |

</details>

## Filters

| Filter                   | Shows                                                                                      |
| ------------------------ | ------------------------------------------------------------------------------------------ |
| Synced from repository   | Baselines kept in step with a GitHub repository.                                           |
| Local changes not pushed | Synced baselines holding changes made in CIPP that have not been pushed to the repository. |
| Not synced               | Baselines that are not linked to a GitHub repository.                                      |

## Table Details

| Column           | Description                                                                        |
| ---------------- | ---------------------------------------------------------------------------------- |
| Baseline         | The name given to the baseline.                                                    |
| Synced From      | The GitHub repository the baseline was imported from or saved to, when it has one. |
| Description      | The free-text description recorded against it.                                     |
| Standards        | How many standards it carries across all of its stages.                            |
| Stages           | The names of its stages, in the order tenants pass through them.                   |
| Assigned Tenants | The tenants and tenant groups the baseline applies to.                             |
| Remediation      | Whether the baseline reports on deviations only, or corrects them automatically.   |
| Updated At       | When the baseline was last saved.                                                  |
| Updated By       | The operator who last saved it.                                                    |

Selecting a row opens the **Baseline Details** flyout. Alongside those values it shows the progress of each stage: how many tenants sit in it, how many standards it applies, the date of the next time-based advance, and the conditions a tenant must meet before it moves into the following stage.

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Baseline</td><td>Opens the baseline in the editor.</td><td>false</td></tr><tr><td>Clone &#38; Edit Baseline</td><td>Opens a copy of the baseline in the editor, leaving the original untouched until you save the copy.</td><td>false</td></tr><tr><td>Run Baseline Now</td><td>Runs the baseline immediately against a single covered tenant, or against every tenant it is assigned to. Standards sitting in report-only stages are compared without anything being changed.</td><td>true</td></tr><tr><td>Save to GitHub</td><td>Uploads the baseline, and every Conditional Access and Intune template it references, to a repository you have write access to. Template packages are expanded to their current members, and tenant assignments are replaced with a placeholder. Greyed out unless the GitHub integration is enabled.</td><td>true</td></tr><tr><td>Delete Baseline</td><td>Removes the baseline. Its standards stop being applied to the assigned tenants from the next run onwards.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../.gitbook/includes/feature-request.md" %}
