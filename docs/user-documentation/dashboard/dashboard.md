---
description: About the Dashboard which includes versions and quick links
---

# Previous Dashboard Experience

This is the previous version of the CIPP dashboard, kept available while the current dashboard settles. It gives a single-page overview of the selected tenant, without the tabbed assessment views of the current dashboard.

{% hint style="warning" %}
This dashboard is retained for continuity and will be removed in a future release. New functionality is only being added to the current dashboard.
{% endhint %}

{% hint style="info" %}
Unlike the current dashboard, this page does not support **All Tenants**. Select a specific tenant to see anything here.
{% endhint %}

## Page Controls

A bar across the top of the page holds three controls.

<details>

<summary>Portals</summary>

Quick links to the Microsoft administration centers for the selected tenant. Which portals appear is controlled by the **Portal Links Configuration** settings on the [user-settings.md](../shared-features/menu-bar/user-settings.md "mention") page.

</details>

<details>

<summary>Executive Report</summary>

Creates a report of key metrics to guide conversations with your client about their Microsoft tenant's security and setup. Before downloading, you can review the report's sections and switch individual ones on or off until the output is what you want. Reports can be custom branded via [branding.md](../cipp/settings/branding.md "mention").

</details>

<details>

<summary>Search</summary>

Searches for users across any tenant by user principal name or display name.

{% hint style="warning" %}
This search depends on Microsoft 365 Lighthouse and only returns results if Lighthouse has been onboarded on your partner tenant. The current dashboard's search does not have this dependency, so if this returns nothing, use universal-search.md instead.
{% endhint %}

</details>

## Current Tenant

A bar beneath the controls shows the essentials for the selected tenant. The tenant ID and default domain can each be copied to the clipboard.

| Field           | Description                                                                     |
| --------------- | ------------------------------------------------------------------------------- |
| Tenant Name     | The tenant's display name.                                                      |
| Tenant ID       | The tenant's directory ID.                                                      |
| Default Domain  | The domain marked as default on the tenant.                                     |
| AD Sync Enabled | Whether directory synchronisation from on-premises Active Directory is enabled. |

## Charts

Three charts sit below the tenant bar.

<details>

<summary>User Statistics</summary>

A pie chart breaking the tenant's users into Licensed Users, Unlicensed Users, Guests, and Global Admins, with the total user count in the center.

{% hint style="info" %}
The chart labels are clickable and filter the chart, so you can isolate a segment to read it more easily.
{% endhint %}

</details>

<details>

<summary>Drift Monitoring</summary>

Where drift data exists for the tenant, a doughnut chart splitting its standards into Aligned Policies, Accepted Deviations, Current Deviations, and Customer Specific Deviations.

Where the tenant has no drift data, this card changes to **Standards Set** instead, showing a bar chart of the standards templates configured across the instance by action: Remediation, Alert, and Report.

</details>

<details>

<summary>SharePoint Quota</summary>

A doughnut chart of the tenant's SharePoint storage, split into free and used, with the actual sizes shown in the labels.

</details>

## Detail Cards

Three cards complete the page.

<details>

<summary>Domain Names</summary>

The verified domains on the tenant. The first three are shown, with **See more...** revealing the rest and **See less** collapsing them again. Each domain can be copied to the clipboard.

</details>

<details>

<summary>Partner Relationships</summary>

The cross-tenant access partners configured on the tenant, each shown as a display name and default domain. As with domains, the first three are shown, with **See more...** revealing the rest.

</details>

<details>

<summary>Tenant Capabilities</summary>

The enabled services on the tenant, drawn from its assigned plans. Only Exchange, AAD Premium, and Windows Defender are reported here.

</details>

{% include "../../../.gitbook/includes/feature-request.md" %}
