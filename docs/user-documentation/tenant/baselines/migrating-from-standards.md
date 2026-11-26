---
description: Move your classic Standards and Drift templates to Baselines
---

# Migrating from Standards

Classic Standards and Drift are in maintenance. They keep working and still receive bug fixes, but new settings and features are only added to Baselines. This page explains how to move your existing templates across with **Migrate from Standards**.

{% hint style="info" %}
Migrating needs permission to edit baselines and access to all tenants. A user limited to specific tenants can preview the migration but cannot run it.
{% endhint %}

## Before You Start

Standards and Baselines never run side by side. Turning on Baselines hides the classic Standards and Drift pages and stops their scheduled runs. From that moment your tenants are only checked and corrected by the baselines you have set up, so plan to migrate straight after turning it on.

Your Standards templates are never changed or deleted by the migration. If you want to go back, turn the Baselines feature off again and the Standards pages and their scheduled runs return as you left them.

## Step 1: Turn On Baselines

1. Go to **CIPP Settings** and open the [Features](../../cipp/settings/features.md) tab.
2. Open the actions menu on the **Baselines** row and choose **Enable Feature**.
3. Reload the page. **Baselines** now appears in the menu under Tenant Administration, in place of Standards.

## Step 2: Preview the Migration

1. Open **Baselines** and select the [Baselines](templates.md) tab.
2. Select **Migrate from Standards**.

The flyout lists every Standards and Drift template it found, with the tenants each one is assigned to and the number of standards it carries. Nothing is changed at this point. Templates that can be converted are ticked for you. Clear the tick against any you would rather leave behind.

Each template carries a status.

| Status      | Meaning                                                                      |
| ----------- | ---------------------------------------------------------------------------- |
| Ready       | The template has not been migrated before and will be created as a baseline. |
| Will update | A baseline already exists for this template and will be brought up to date.  |
| Up to date  | An existing baseline already matches the template, so nothing is done.       |
| Skipped     | The template cannot be converted. The row explains why.                      |

Notes in orange under a template tell you about anything that needs your attention after migrating, such as a setting that could not be carried over or a template with no tenants assigned. Read these before you continue.

## Step 3: Choose the Options

| Option                                                                                                                     | Description                                                                                                                                                                                |
| -------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Import everything as report-only (recommended)                                                                             | Brings every standard across with automatic fixing switched off. CIPP reports what deviates but changes nothing in your tenants until you turn automatic fixing back on for a standard.    |
| Migrated drift templates should also alert on Intune and Conditional Access policies that were not created from a template | Adds detection of policies that exist in the tenant but were never deployed from a template, so they show up as deviations. This matches how Drift reported unknown policies.               |

We recommend leaving report-only on. With it off, standards that were set to remediate in the template start correcting tenants on the first baseline run.

## Step 4: Migrate

Select **Migrate** at the bottom of the flyout. The list updates to show what happened to each template.

| Status   | Meaning                                                       |
| -------- | ------------------------------------------------------------- |
| Migrated | The template was created as a new baseline.                   |
| Updated  | An existing baseline was brought up to date.                  |
| Failed   | The conversion did not complete. The row explains why.        |

Close the flyout. The new baselines appear in the list with the same names as your templates.

## What Is Carried Over

| From your template                | In the baseline                                                                                                                                      |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| Name and description              | Kept as they are.                                                                                                                                    |
| Assigned and excluded tenants     | Kept as they are, including tenant groups and All Tenants.                                                                                           |
| Standards and their settings      | Each standard is added to a single stage called **Default** with the settings you had.                                                               |
| Report, alert and remediate       | Alerting is kept. Remediation is kept only when report-only is switched off during migration.                                                        |
| Run manually                      | The baseline arrives with **Disable Scheduled Runs** on, so it only runs when you start it.                                                          |
| Drift templates                   | Become baselines that report and alert without automatic fixing, the same way Drift worked. The alert email address and webhook are carried over.    |
| Intune and other template choices | Each selected template becomes its own entry in the baseline. Intune templates chosen by tag follow the tag, so templates you tag later are included. |

A template that was assigned to the **Template Tenant** placeholder, such as one imported from a repository, arrives without real tenants. Open it in the [baseline editor](template.md) and assign tenants before it does anything.

## After Migrating

1. Open each new baseline in the [baseline editor](template.md) and check the standards and tenants against the notes from the preview.
2. Use **Run Baseline Now** on the [Baselines](templates.md) tab, or wait for the next scheduled run.
3. Review the results on the [Alignment](alignment.md) page. Accept the deviations a tenant is allowed to keep, and create any tenant overrides you need.
4. When the results look right, turn on **Automatically fix this when the setting drifts** for the standards CIPP should correct, either per standard or with **Set all standards to** in the editor.

Tenant overrides cannot be prepared before migrating, which is another reason to import as report-only first.

## Migrating Again

You can run **Migrate from Standards** as often as you like. A template that has not changed since it was migrated shows as **Up to date** and is left alone. A template that has changed shows as **Will update** and updates the same baseline, so the deviations you accepted or denied are kept. Updating replaces the baseline's standards with the template's, so changes you made to that baseline in the editor are lost. Clear its tick if you want to keep them.

{% include "../../../../.gitbook/includes/feature-request.md" %}
