---
description: View and manage your Microsoft 365 CSP tenants.
---

# Tenants

{% hint style="warning" %}
When you select one of the portal links, the permissions of the currently logged in user are the ones that matter. The user's GDAP permissions will apply, not the CIPP service account.
{% endhint %}

Lists every tenant CIPP manages and gives you a one click jump into each Microsoft administration center for that customer. The portal links open in the context of the selected tenant using your own partner credentials, so you land in the target administration center already scoped to that customer rather than having to switch context manually. Alongside the links, the row actions cover the tenant level maintenance tasks: editing the tenant's alias and group membership, managing its configuration backup schedule, and clearing its cached capability data.

Tenants are served from CIPP's own cache rather than being read from Partner Center on every page load. If a newly added tenant is missing, or the display name or default domain looks out of date, clear the tenant cache from the Cache card in [settings](../../../cipp/settings/ "mention") using the **Clear Cache** button with **Only Clear the Tenant Cache** enabled. That queues a tenant refresh in the background. Refreshing your browser afterwards is worth doing so the page picks up the new data.

## Table Details

| Column              | Description                                                                                                                                                                                                       |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Display Name        | The tenant's name as it appears in Microsoft 365. If you have set a tenant alias, that alias is shown instead.                                                                                                    |
| Default Domain Name | The tenant's default domain, used throughout CIPP as the tenant identifier.                                                                                                                                       |
| Tenant Groups       | The tenant groups this tenant belongs to, with each group's `static` or `dynamic` type. Only groups you have access to are listed. Groups are created and maintained on [groups](groups/ "mention").              |
| M365                | Opens the Microsoft 365 admin center for the tenant.                                                                                                                                                              |
| Exchange            | Opens the Exchange admin center for the tenant.                                                                                                                                                                   |
| Entra               | Opens the Microsoft Entra admin center for the tenant.                                                                                                                                                            |
| SharePoint          | Opens the SharePoint admin center for the tenant. Unlike the other portals, the SharePoint admin host name cannot be derived from the tenant, so the first use resolves it through Graph and caches it for later. |
| Teams               | Opens the Teams admin center for the tenant.                                                                                                                                                                      |
| Azure               | Opens the Azure portal for the tenant.                                                                                                                                                                            |
| Intune              | Opens the Intune admin center for the tenant.                                                                                                                                                                     |
| Security            | Opens the Microsoft Defender portal for the tenant.                                                                                                                                                               |
| Purview             | Opens the Microsoft Purview portal for the tenant.                                                                                                                                                                |
| Power Platform      | Opens the Power Platform admin center for the tenant.                                                                                                                                                             |
| Power BI            | Opens the Power BI admin portal for the tenant.                                                                                                                                                                   |

{% hint style="info" %}
A tenant that repeatedly fails to return data from Graph accumulates errors against its record and is eventually dropped from the standard tenant list. If a tenant you expect to see is missing entirely, check its relationship health and permissions before assuming it is a caching problem.
{% endhint %}

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Edit Tenant</td><td>Opens the <a data-mention href="../../manage/edit.md">edit.md</a> page, where you can set a tenant alias, manage tenant group membership, define custom variables, and configure offboarding defaults.</td><td>false</td></tr><tr><td>Configure Backup</td><td>Opens the <a data-mention href="../../manage/backup.md">backup.md</a> page for the tenant, where you can review the backup schedule, choose which components are included, and trigger a backup.</td><td>false</td></tr><tr><td>Delete Capabilities Cache</td><td>Clears the cached license capability data CIPP holds for the tenant, so the next request re-evaluates what the tenant is licensed for. Useful after a license change has not yet been reflected in CIPP. You are asked to confirm before the cache is removed.</td><td>true</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
