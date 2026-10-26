---
description: Fleet-wide view of how your tenants measure up against their baselines
---

# Baselines

{% hint style="info" %}
Baselines is controlled by the **Baselines** flag on the [features.md](../../cipp/settings/features.md "mention") tab of CIPP settings. It is on by default for installs that have no classic Standards templates, and off by default for installs that do. It sits behind a flag because turning it on switches off Standards and Drift, so you decide when your tenants move from one to the other.
{% endhint %}

A baseline is the desired configuration for your tenants. CIPP checks every assigned tenant against it twice a day, shows exactly what deviates, and, where you allow it, corrects the deviation automatically. Standards are grouped into stages so a baseline can roll out gradually, with each stage adding more of the configuration as a tenant graduates into it.

Baselines supersede the classic Standards and Drift pages. While the flag is on, those pages and their scheduled runs are turned off, so only one engine manages your tenants at a time. Your existing Standards templates can be brought across with **Migrate from Standards** on the [Baselines](templates.md) page.

The Fleet Overview is the landing screen for the feature and summarises every tenant covered by a baseline. Use the tabs at the top to move between this overview, [Alignment](alignment.md), and the list of [Baselines](templates.md) themselves.

## Overview

{% @storylane/embed subdomain="app" linkValue="oyzpk0zn7v1m" url="https://app.storylane.io/share/oyzpk0zn7v1m" %}

## First Run

Until you have created a baseline, the overview is replaced by a **Welcome to Baselines** card that explains the three steps needed to make the dashboard useful: create a baseline and add standards to it, assign the tenants or tenant groups it applies to, then save and run the first check. Nothing is changed in a tenant until you enable automatic fixing on an individual standard.

The card carries two buttons.

| Button                       | Description                                                                              |
| ---------------------------- | ---------------------------------------------------------------------------------------- |
| Create your first baseline   | Opens the [baseline editor](template.md) on a new, empty baseline.                       |
| Browse the community catalog | Opens the list of [Baselines](templates.md), where ready-made baselines can be imported. |

## Filtering by Baseline

Use the **Baseline** and **Stage** selectors at the top of the page to see how a single baseline, or one stage of it, is doing. The scores, charts and tables then count only the tenants assigned to that baseline and the standards it has rolled out to each of them; picking a stage narrows this to that stage's standards for tenants that have reached it. Standards shared with another baseline are scored once per tenant, so they count toward every baseline that includes them. Trend history is kept for the whole fleet only, so the trend chart is hidden while a filter is applied.

The Alignment tab's Standard View has the same **Baseline** and **Stage** selectors, and the Open Deviations and License Missing tiles keep the selected filter when you click through to it.

## Score Bar

Four tiles across the top of the page summarise the whole fleet.

| Tile                               | Description                                                                                                                                           |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| Compliant with accepted deviations | The share of standards that count as aligned, including deviations you have accepted. The tooltip shows how much of the score comes from acceptances. |
| Compliant with baseline            | The share of standards genuinely in their expected state, with accepted deviations excluded.                                                          |
| Open Deviations                    | The number of deviations awaiting a decision. Selecting the tile opens Alignment filtered to those deviations.                                        |
| License Missing                    | The share of standards left out of scoring because the tenant is not licensed for them. Selecting the tile opens Alignment filtered to those rows.    |

## Fleet Compliance Trend

Plots both compliance figures over the last 14 days, so you can see whether the estate is improving. Trend data appears after the first baseline has run.

## Deviation States

A breakdown of every applicable standard across the fleet by its current state: Compliant, Accepted, Drift, or Denied.

## Tenants Needing Attention

The five lowest-scoring tenants, each with a progress bar showing how closely it matches its baselines. Selecting a tenant switches to it and opens the [Alignment](alignment.md) page, ready for you to triage its deviations or produce a What-If Report.

## Accepted & Denied Deviations

Every deviation you have already ruled on, across all tenants.

| Column   | Description                                                              |
| -------- | ------------------------------------------------------------------------ |
| Tenant   | The tenant the deviation was found in.                                   |
| Standard | The standard that deviates from its baseline.                            |
| Status   | Whether the deviation was accepted, or denied and queued for correction. |
| Reason   | The justification recorded when the decision was made.                   |
| Set By   | The operator who made the decision.                                      |
| Expires  | When an acceptance lapses, after which the deviation is raised again.    |

{% include "../../../../.gitbook/includes/feature-request.md" %}
