# Table View

The Table Overview presents Secure Score as a single sortable, searchable table, which is the faster way to scan a long list or export it. With a single tenant selected it lists that tenant's recommendations; with All Tenants selected it lists every recommendation for every tenant. The card view is on [.](./ "mention"), and the per-tenant score table for All Tenants sits there too.

## All Tenants View

Selecting All Tenants replaces the recommendation list with one row per tenant per recommendation, drawn from CIPP's nightly score cache rather than live calls to Microsoft. Rows are sorted lowest score first. Only recommendations a tenant actually reports appear; the Controls tab counts the tenants that do not.

| Column        | Description                                                                                                   |
| ------------- | ------------------------------------------------------------------------------------------------------------- |
| Tenant Name   | The tenant's display name.                                                                                    |
| Control Name  | Microsoft's identifier for the recommendation.                                                                |
| Title         | The name of the recommendation.                                                                               |
| Score Percent | How complete the recommendation is for that tenant, coloured green at 100%, amber when partial, red at 0%.    |
| Points        | The points earned out of the maximum available for the recommendation.                                        |
| Tier          | Core, Defense in Depth, or Advanced.                                                                          |
| State         | How the recommendation has been handled: Default, Ignored, ThirdParty and so on.                              |

User impact, implementation cost, category, threats, tenant groups, and who changed the state, when and why are available from the column picker.

The filter presets narrow the list by completion (**Not complete**, **Complete**, **Partial**, **Not started**, **No data**), by tier and by state. The **Tenant groups** picker limits it to tenants in any of the ticked CIPP tenant groups. Arriving from the Controls tab shows only the chosen recommendation, under a **Control:** preset.

Selecting a row opens its details: the score, tier, impact, cost, state history and threats, followed by Microsoft's description, remediation guidance and remediation impact. **Open tenant secure score** switches to that tenant's own Secure Score page, and **Open in admin portal** opens the recommendation in the Microsoft portal. The view is read-only; change a recommendation's status from the tenant's own Secure Score page.

{% hint style="info" %}
Scores appear only after the nightly cache job has run. Until then the page says so rather than showing an empty table, and a newly added tenant will not appear until the next refresh.
{% endhint %}

The sections below describe the single-tenant view.

## Score Summary

The same four figures shown on the card view run across the top of the page.

| Tile                             | Description                                                                         |
| -------------------------------- | ----------------------------------------------------------------------------------- |
| Current Score                    | The tenant's current score as a percentage of the maximum score available to it.    |
| Compared score (All Tenants)     | The average score Microsoft reports across all tenants, for comparison.             |
| Compared score (Similar Tenants) | The average score Microsoft reports for tenants of a comparable size.               |
| Score in points                  | The current score and the maximum available, in points rather than as a percentage. |

## Table Details

Each row is one Secure Score recommendation, combining the tenant's own control scores with the control descriptions Microsoft publishes.

| Column      | Description                                                                                                                                                       |
| ----------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Title       | The name of the recommendation.                                                                                                                                   |
| Tier        | Where the recommendation sits in Microsoft's layering of controls: Core, Defense in Depth, or Advanced.                                                           |
| Action Url  | Where the recommendation is actioned. This is normally a link into the relevant Microsoft portal but reads as a path within CIPP where a CIPP standard covers it. |
| User Impact | How disruptive Microsoft considers the change to be for end users: Low, Moderate, or High.                                                                        |
| Threats     | The threat categories the recommendation mitigates, such as account breach, data exfiltration, or elevation of privilege.                                         |

These columns are drawn from the Graph resource type `secureScoreControlProfile`. For more information on the underlying properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/securescorecontrolprofile?view=graph-rest-1.0#properties).

{% hint style="info" %}
The single-tenant view is read-only and does not show how complete each recommendation is. To see completion, change a recommendation's status, or read its full remediation guidance, use ..
{% endhint %}

{% include "../../../../../.gitbook/includes/feature-request.md" %}
