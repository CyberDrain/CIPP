---
description: See where tenants deviate from their baselines, and decide what to do about it
---

# Baseline Alignment

This page shows how tenants measure up against the baselines assigned to them, and is where deviations are triaged. The same data is presented four ways, and you switch between them with the toggle above the table. Each view carries its own columns, filters, and actions.

| View          | Use it to                                                                        |
| ------------- | -------------------------------------------------------------------------------- |
| Tenant View   | Work through every standard applicable to the tenant you have selected.          |
| Standard View | See how a single standard is faring across the whole estate.                     |
| Baseline View | See which tenants a baseline covers, and how far each has progressed its stages. |
| Historic View | Read every recorded run and operator decision for the selected tenant.           |

## Deviation States

Every row in the Tenant and Standard views carries a state.

| State                      | Meaning                                                                                                                                                                       |
| -------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Compliant                  | The setting matches what the baseline expects.                                                                                                                                |
| Drift                      | The setting differs from the baseline and is awaiting a decision.                                                                                                             |
| Accepted                   | The deviation has been accepted, so the tenant counts as aligned until the acceptance expires.                                                                                |
| Partially Accepted         | Individual properties of the setting have been accepted, but others still deviate.                                                                                            |
| Denied - Remediate Pending | The deviation was denied, and the setting is corrected back to the baseline on the next run.                                                                                  |
| Denied - Delete Pending    | The deviation was denied, and the offending policy is removed on the next run.                                                                                                |
| Error                      | The last attempt to correct the setting failed, so it cannot be accepted or denied. The run logs explain why. A deviation already denied keeps its **Denied** state instead. |
| Conflict                   | Two baselines configure the same standard at the same assignment level with different settings, so nothing is compared or corrected. Edit one of the baselines to resolve it. |
| Skipped - No License       | The tenant is not licensed for the standard, so it is left out of scoring.                                                                                                    |
| No Data                    | Nothing has been collected for the standard yet.                                                                                                                              |

## Tenant View

The view opens on the tenant currently selected, and is laid out as a score bar, the baselines assigned to that tenant, and the table of applicable standards.

### Score Bar

| Tile                               | Description                                                                                                                                         |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Compliant with accepted deviations | The share of standards counting as aligned, including deviations you have accepted. The tooltip shows how much of the score comes from acceptances. |
| Compliant with baseline            | The share of standards genuinely in their expected state, with accepted deviations excluded.                                                        |
| Open Deviations                    | How many deviations are awaiting a decision.                                                                                                        |
| License Missing                    | The share of standards left out of scoring because the tenant is not licensed for them.                                                             |

### Assigned Baselines

One card per baseline assigned to the tenant, showing how closely the tenant matches the standards rolled out to it so far, which stage it is in, and what has to happen before it reaches the next one. Where the next stage needs manual approval the card is marked **Awaiting approval** and carries a **Move to next stage** button, which applies that stage's standards on the following run.

Where the next stage is reached automatically, the card instead carries **Re-evaluate stage conditions**, which checks the tenant against that stage's conditions straight away rather than waiting for the next scheduled check. If the conditions are met, the tenant moves into the stage and receives its standards on the following run; if not, the result lists the conditions still unmet.

### What-If Report

Produces a client-ready report previewing what the configured standards would change for the tenant, including the stages still to come. The preview opens in a dialog and can be downloaded as a PDF.

| Option                        | Description                                                                                                            |
| ----------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| Branding                      | The branding preset the report is styled with. Presets are managed in Settings, under Branding.                        |
| Simulate additional baselines | Adds baselines the tenant is not assigned to, so everything they would bring appears in the report as planned changes. |
| What Is Already In Place      | Includes the policies already deployed and the settings already enforced, with their values.                           |
| Rollout Stages                | Includes how the remaining stages arrive and when.                                                                     |

**What Is Already In Place** and **Rollout Stages** each switch their section of the report on and off. Changes are reflected in the preview as you make them.

While a run is in progress a tracker appears next to the view toggle, showing its progress.

### Filters

| Filter          | Shows                                                                     |
| --------------- | ------------------------------------------------------------------------- |
| Open Deviations | Standards that deviate from the baseline and have not yet been ruled on.  |
| Accepted        | Standards whose deviation has been accepted.                              |
| Denied          | Standards whose deviation was denied and which are queued for correction. |
| License Missing | Standards excluded from scoring because the tenant is not licensed.       |

### Table Details

| Column        | Description                                                                                    |
| ------------- | ---------------------------------------------------------------------------------------------- |
| Standard      | The standard being checked.                                                                    |
| Category      | The area of Microsoft 365 the standard covers.                                                 |
| Stage         | The stage of its baseline the standard belongs to.                                             |
| Status        | The current deviation state, as listed above.                                                  |
| Reason        | The justification recorded when the deviation was accepted or denied.                          |
| Set By        | The operator who made that decision.                                                           |
| Set At        | When the decision was made.                                                                    |
| Expires       | When an acceptance lapses, after which the deviation is raised again.                          |
| Configured By | The baseline whose settings are in force for this tenant, or Tenant Override where one is set. |
| Last Run      | When the standard was last checked.                                                            |

Selecting a row opens the **Standard Details** flyout. It lists every baseline configuring the standard for this tenant and marks which one is effective, as the most specific assignment wins, and shows whether each one fixes drift automatically and whether it raises alerts.

Below that, the expected and current configurations are compared property by property, with each deviating property marked. An individual property can be accepted on its own, which tolerates only that value and still raises a deviation if anything else changes. Where the standard detects policies that no baseline covers, the offending policy can be opened and read in full, and can be denied and queued for deletion. The flyout also carries any manual task instructions, and the most recent runs for the standard, each of which can be expanded to show exactly what was expected and what was found. **View Logs** beside **Last Run**, and on each recent run, opens the log entries for that run.

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Compare Now</td><td>Re-checks the standard against the tenant without changing anything. Greyed out for rows in <strong>Conflict</strong>.</td><td>true</td></tr><tr><td>Remediate Now</td><td>Applies the expected configuration to the tenant immediately, once, whatever the standard's own remediation setting says. Greyed out for rows in <strong>Conflict</strong>, and not offered for manual tasks.</td><td>true</td></tr><tr><td>Accept Deviation</td><td>Records the deviation as accepted, so the tenant counts as aligned and alerts stop until the acceptance expires. You give a reason, optionally an expiry date, and whether the setting should be corrected automatically when the acceptance lapses. Greyed out unless the row is in <strong>Drift</strong> or <strong>Partially Accepted</strong>, and not offered for manual tasks.</td><td>true</td></tr><tr><td>Deny &#38; Fix Deviation</td><td>Rejects the deviation, so it is corrected back to the baseline on the next run regardless of the configured remediation setting. The fix happens once, so if the setting drifts again it shows as a new deviation. Greyed out unless the row is in <strong>Drift</strong> or <strong>Partially Accepted</strong>, and not offered for manual tasks.</td><td>true</td></tr><tr><td>Undo Accept/Deny</td><td>Clears the accept or deny decision along with any accepted properties, so the deviation surfaces again on the next run. Greyed out where no decision has been recorded, and not offered for manual tasks.</td><td>true</td></tr><tr><td>Mark Task Complete</td><td>Marks a manual task as done for this tenant. It is raised again on the recurrence the task defines. Only offered for manual tasks, and greyed out unless the task is in <strong>Drift</strong>.</td><td>true</td></tr><tr><td>Create Tenant Override</td><td>Configures the standard for this one tenant, replacing whatever the baseline applies. The settings are pre-filled with what is currently in force. Greyed out where an override already exists or the standard has no configurable settings, and not offered for manual tasks.</td><td>false</td></tr><tr><td>Remove Tenant Override</td><td>Deletes the tenant override, so the tenant falls back to the baseline's configuration on the next run. Greyed out where no override is set, and not offered for manual tasks.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
Unlike **Remediate** in classic Standards, neither Remediate Now nor Deny & Fix Deviation keeps a setting fixed. To correct a standard every time it drifts, turn on **Automatically fix this when the setting drifts** in the [baseline editor](template.md).
{% endhint %}

## Standard View

One row per standard, aggregated across every tenant it applies to.

The **Baseline** and **Stage** selectors above the table narrow the view to one baseline, and optionally one of its stages. **Stage** is greyed out until a baseline is chosen. The counts then cover only the standards that baseline has rolled out. Standards shared with another baseline are scored once per tenant, so they count toward every baseline that includes them. The [Fleet Overview](README.md "mention") tiles open this view with their filter already applied.

### Filters

| Filter                  | Shows                                                                         |
| ----------------------- | ----------------------------------------------------------------------------- |
| Has Open Deviations     | Standards deviating on at least one tenant and awaiting a decision.           |
| Has Accepted Deviations | Standards with at least one accepted deviation.                               |
| Has License Missing     | Standards excluded from scoring on at least one tenant for want of a licence. |

### Table Details

| Column                             | Description                                                              |
| ---------------------------------- | ------------------------------------------------------------------------ |
| Standard                           | The standard being checked.                                              |
| Category                           | The area of Microsoft 365 the standard covers.                           |
| Impact                             | How disruptive applying the standard is likely to be.                    |
| Compliant with accepted deviations | The share of tenants counting as aligned, including accepted deviations. |
| Compliant with baseline            | The share of tenants genuinely in the expected state.                    |
| Accepted                           | How many tenants have an accepted deviation for the standard.            |
| Open Drift                         | How many tenants are deviating and awaiting a decision.                  |
| License Missing                    | How many tenants are excluded from scoring for want of a licence.        |
| Tenants                            | How many tenants the standard applies to in total.                       |

Selecting a row opens the **Standard Tenant Summary** flyout, which adds the Secure Score points the standard is worth, a compliance trend once there is more than one day of data, and a card per tenant giving its state. Deviating tenants can be accepted or given a tenant override directly from those cards.

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Deploy To All Tenants</td><td>Applies the standard's configured expected value to every applicable tenant. Accepted and suppressed deviations are left alone. Not offered for manual tasks.</td><td>true</td></tr><tr><td>Mark Task Complete (All Tenants)</td><td>Marks a manual task as done for every applicable tenant. Each raises it again on the recurrence the task defines. Only offered for manual tasks.</td><td>true</td></tr><tr><td>Compare All Tenants</td><td>Re-checks the standard on every tenant without changing anything.</td><td>true</td></tr><tr><td>Edit Baseline</td><td>Opens the baseline that configures the standard in the editor.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

## Baseline View

One row per baseline, with the tenants it covers and how far the rollout has progressed.

### Table Details

| Column           | Description                                                                      |
| ---------------- | -------------------------------------------------------------------------------- |
| Baseline         | The name given to the baseline.                                                  |
| Standards        | How many standards it carries across all of its stages.                          |
| Stages           | The names of its stages, in the order tenants pass through them.                 |
| Assigned Tenants | The tenants and tenant groups the baseline applies to.                           |
| Remediation      | Whether the baseline reports on deviations only, or corrects them automatically. |
| Updated At       | When the baseline was last saved.                                                |

Selecting a row opens the **Baseline Rollout** flyout, which gives a card per tenant showing the stage it is in, when it entered that stage, what has to happen before it advances, and an estimate of when that will be. Tenants waiting on manual approval carry a **Move to Next Stage** button. Tenants whose next stage is reached automatically carry **Re-evaluate Stage** instead, which checks that stage's conditions for the tenant straight away, in the same way as **Re-evaluate stage conditions** on the tenant's own card.

### Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Baseline</td><td>Opens the baseline in the editor.</td><td>false</td></tr><tr><td>Run Baseline Now</td><td>Runs the baseline immediately against a single covered tenant, or against every tenant it is assigned to. Standards sitting in report-only stages are compared without anything being changed.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

## Historic View

A timeline of everything recorded for the selected tenant: scheduled and manual runs, and the decisions operators have made. Runs are collapsed into a single entry carrying a count per outcome, which expands to the individual standards. Entries where an alert was sent are marked, and each run can be opened to show its logs.

The timeline can be narrowed by standard, outcome, and run type, or searched, and loads in blocks of fifty entries.

| Outcome                      | Meaning                                                          |
| ---------------------------- | ---------------------------------------------------------------- |
| Compliant                    | The standard was verified as matching the baseline.              |
| Remediated                   | The standard was changed back to the expected configuration.     |
| Drift                        | The standard was found to deviate.                               |
| Error                        | The change failed. The run logs explain why.                     |
| Skipped - No License         | The tenant is not licensed for the standard.                     |
| Skipped - No Data            | Nothing had been collected for the standard yet.                 |
| Accepted                     | An operator accepted the deviation.                              |
| Property Accepted            | An operator accepted a single property of the setting.           |
| Denied - Remediation Ordered | An operator denied the deviation and ordered it corrected.       |
| Denied - Delete Ordered      | An operator denied the deviation and ordered the policy removed. |
| Property Denied              | An operator denied a single property of the setting.             |
| Triage Cleared               | An earlier accept or deny decision was cleared.                  |
| Property Triage Cleared      | An earlier decision on a single property was cleared.            |
| Task Completed               | A manual task was marked as done.                                |
| Override Created             | A tenant-specific override of the standard was created.          |
| Override Removed             | A tenant-specific override was deleted.                          |
| Stage Advanced               | The tenant moved into the next stage of a baseline.              |
| Deleted                      | A policy was removed after its deviation was denied.             |
| Delete Failed                | The removal did not complete. The run logs explain why.          |

{% include "../../../../.gitbook/includes/feature-request.md" %}
