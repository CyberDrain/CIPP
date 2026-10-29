# Secure Score

The Tenant Overview presents Microsoft Secure Score. With a single tenant selected it shows that tenant's current standing and every recommendation Microsoft makes for it, one card per recommendation, ordered by the points still to gain with the biggest win first. With All Tenants selected it shows an estate-wide summary and a table of every tenant's score instead. The same data is available as a table on table.md, and with All Tenants selected a third tab, controls.md, compares each recommendation across the estate.

## All Tenants View

Selecting All Tenants replaces the cards with a portfolio view, built from CIPP's nightly score cache rather than live calls to Microsoft. Four figures run across the top.

| Tile               | Description                                                                                                                   |
| ------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| Portfolio average  | The average of every tenant's latest cached score. Hover to see how many tenants it covers.                                   |
| Change over N days | How far the portfolio average has moved across the retained history, in points. The heading names the number of days covered. |
| Highest            | The best scoring tenant's percentage. Hover to see which tenant it is and its score in points.                                |
| Lowest             | The lowest scoring tenant's percentage, with the same detail on hover.                                                        |

**Portfolio trend** charts the daily average across the retained history. Each day is averaged only over the tenants that reported a score that day, so a tenant that started reporting part way through the window does not drag the earlier points down.

**Top 5** and **Bottom 5** rank the estate by score, with a coloured bar per tenant: green at 75% or above, amber from 50%, red below that. Selecting a tenant opens its own Secure Score page and switches the tenant selector to it. Ranks are estate-wide, so #1 is the best scoring tenant in the estate rather than the best of five. The two boards never overlap: Bottom 5 takes the lowest five and Top 5 takes whatever remains, so an estate with fewer than ten scored tenants shows a shorter Top 5.

**Secure score by tenant**, below the summary, lists one row per tenant, sorted lowest score first so the tenants that need attention are at the top.

| Column           | Description                                                                                         |
| ---------------- | --------------------------------------------------------------------------------------------------- |
| Tenant Name      | The tenant's display name, falling back to its domain where no name is recorded.                    |
| Tenant           | The tenant's default domain.                                                                        |
| Percentage Score | The tenant's latest score as a percentage of the maximum available to it.                           |
| Change           | How far the tenant's score has moved across the retained history, in percentage points.             |
| Current Score    | The latest score in points.                                                                         |
| Max Score        | The maximum score available to that tenant.                                                         |
| Captured At      | When the score CIPP is showing was recorded.                                                        |
| Tenant Groups    | The CIPP tenant groups the tenant belongs to. Hidden by default; enable it from the column picker. |

The **Tenant groups** picker above the table limits it to tenants in any of the CIPP tenant groups you tick; with none ticked it shows every tenant. **View tenant secure score** opens the selected tenant's own Secure Score page and switches the tenant selector to it.

{% hint style="info" %}
Scores appear only after the nightly cache job has run, so a newly added tenant shows nothing until the next refresh. Tenants with no maximum score recorded are left out of the average and the leaderboards entirely. Excluded tenants never appear, even when older cached scores for them remain.
{% endhint %}

The filters, cards and actions described below apply to the single-tenant view.

## Score Summary

Four figures run across the top of the page.

| Tile                             | Description                                                                         |
| -------------------------------- | ----------------------------------------------------------------------------------- |
| Current Score                    | The tenant's current score as a percentage of the maximum score available to it.    |
| Compared score (All Tenants)     | The average score Microsoft reports across all tenants, for comparison.             |
| Compared score (Similar Tenants) | The average score Microsoft reports for tenants of a comparable size.               |
| Score in points                  | The current score and the maximum available, in points rather than as a percentage. |

Below them, the **Secure Score** card charts the last seven score readings Microsoft has recorded for the tenant, each labelled by how long ago it was taken, so recent movement is visible at a glance. The **%** / **Points** toggle on the card switches the chart between the score as a percentage of the maximum (the default) and the score in points.

## Filters

The filter button above the cards limits which recommendations are shown. The current selection is shown on the button itself.

| Filter                | Description                                                                         |
| --------------------- | ----------------------------------------------------------------------------------- |
| All Recommendations   | Shows every recommendation regardless of status.                                    |
| Completed (100%)      | Shows only recommendations that are fully complete.                                 |
| Not Started (0%)      | Shows only recommendations with no progress at all.                                 |
| In Progress (Started) | Shows recommendations that are partially complete, meaning anything from 1% to 99%. |
| Not Completed (Started + Not Started) | Shows every recommendation below 100%, combining the two filters above. |

## Sorting

The sort button next to the filter sets the order of the cards. The current selection is shown on the button itself.

| Sort             | Description                                                                                     |
| ---------------- | ----------------------------------------------------------------------------------------------- |
| Points to gain   | The default. Recommendations worth the most remaining points come first.                        |
| Implementation % | Orders by how complete each recommendation is, with the most complete first.                    |

## Recommendation Cards

Each card covers one recommendation and carries the following, where Microsoft supplies it:

* A chip showing how complete the recommendation is, coloured green at 100%, amber above 50%, and red at 50% or below. A recommendation marked as handled elsewhere also reads "Resolved by Third Party".
* A chip showing what completing the recommendation is worth, such as **+6 pts (+2.21% total)**: the points still available on it and how much the tenant's overall score would rise. Completed recommendations show +0. The chip is left out where Microsoft does not publish a maximum for the recommendation.
* **Description**, explaining what the recommendation covers.
* **Remediation Recommendation**, explaining how to satisfy it. Where a CIPP standard covers the recommendation, this points to that standard instead of Microsoft's own instructions. It is hidden once the recommendation reaches 100%.
* **Threats**, the threat categories the recommendation mitigates.
* **Compliance Frameworks**, the certifications and controls the recommendation maps to.

## Card Actions

| Action        | Description                                                                                                                                                                                                                         |
| ------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Change Status | Records how the recommendation has been handled, choosing a resolution type and a reason. Unavailable, and shown greyed out, for Microsoft Defender controls.                                                                       |
| Remediate     | Opens the Microsoft portal page for the recommendation in a new tab. Where a CIPP standard covers the recommendation, it opens that standard on the Baselines page, or on the standards list where Baselines is turned off. |
| Updates       | Lists the status changes recorded against the recommendation, showing the state set, who it was assigned to, the reason given, who made the change and when. Only shown where changes exist, with the number of them on the button. |

### Resolution types

**Change Status** offers three resolutions, along with a reason that is stored as the comment against the control and is visible in the Microsoft portal as well as in CIPP.

| Resolution type         | Description                                                                                                                                                |
| ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Resolved by Third Party | The recommendation is satisfied by a product outside Microsoft 365. Marks it complete and awards the points.                                               |
| Ignored / Risk Accepted | The recommendation is not going to be actioned. Marks it complete without awarding the points.                                                             |
| Mark as default         | Hands the recommendation back to Microsoft's own detection, awarding points only when Microsoft sees it as complete. Use this to undo either of the above. |

{% hint style="warning" %}
Marking a recommendation as resolved by a third party or as risk accepted changes the tenant's score in Microsoft's own reporting, not just in CIPP. Record a reason that will still make sense to whoever reads it months later, since it is the only record of why the score was adjusted.
{% endhint %}

{% hint style="info" %}
Defender controls cannot be updated from here at all. Microsoft only accepts status changes for those through the Microsoft Defender portal, so **Change Status** is disabled on those cards and the API rejects the change if it is attempted another way.
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
