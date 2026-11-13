# Tenant Select

The tenant selector sits at the top of CIPP and controls which tenant you are managing. Changing it reloads the data on the current page for the newly selected tenant, and cancels any requests still running for the previous one.

## Selecting a Tenant

Tenants are listed as their display name followed by their default domain in brackets. Start typing to narrow the list by either part, then choose a tenant to switch to it.

**\*All Tenants** is pinned to the top of the list. Selecting it shows data across every tenant you manage on pages that support it. Some pages behave differently under All Tenants, most notably tables, which always read from cached data in this mode. It is left out of the list when every custom role you hold has **Block the All Tenants view** switched on. See [add.md](../../cipp/advanced/authentication/cipp-roles/add.md "mention").

The tenant you are currently on stays in the list in its usual position, marked with a **Current** chip, and the list scrolls to it when you open the dropdown.

The circular arrows button beside the selector reloads the tenant list. Use it when the list looks stale, for example after tenants have been added or removed since you opened CIPP.

The selected tenant is reflected in the page address as a `tenantFilter` parameter, so any CIPP page can be linked to with a tenant already chosen. The parameter accepts the tenant's default domain, its initial `onmicrosoft.com` domain, or its tenant ID, and CIPP rewrites the address to the default domain once the page loads.

{% hint style="info" %}
Your selected tenant is remembered between sessions. If you open CIPP at a page with no tenant in its address, the tenant you last used is applied automatically.
{% endhint %}

## Favourites and Recent Tenants

The list is grouped, so the tenants you work with most sit at the top rather than buried in an alphabetical list of everything you manage.

| Group           | Description                                                                                                                        |
| --------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **Favorites**   | Tenants you have starred, sorted alphabetically.                                                                                   |
| **Recent**      | The tenants you have selected most recently, newest first, up to eight. A tenant that is already a favourite is not repeated here. |
| **All tenants** | Every tenant you manage, sorted alphabetically.                                                                                    |
| **Tenant groups** | Your tenant groups, sorted alphabetically. Shown only when tenant groups are turned on for the selector. See [#tenant-groups](tenant-select.md#tenant-groups "mention"). |

Favourites and Recent are shortcuts rather than a move: a tenant listed there still appears in its usual alphabetical position under **All tenants** as well.

Each row carries a star on the right. Select it to add that tenant to **Favorites**, or select it again to remove it. Selecting the star does not change tenant, so you can reorganise the list without leaving the page you are on.

Recent tenants are tracked for you: choosing a tenant from the dropdown adds it to the top of the group. **\*All Tenants** is excluded from both groups and cannot be starred, since it is already pinned above them. Tenant groups are excluded in the same way.

To hide the **Recent** group, switch off **Show Recent Tenants in Tenant Selector** on the Preferences page. See [user-settings.md](user-settings.md "mention").

{% hint style="info" %}
Favourites and recent tenants are stored in your browser rather than in your CIPP user settings. They are specific to the browser and device you set them on, they do not follow you to another machine, and clearing your browser's site data removes them. Both lists update immediately in any other CIPP tab you have open.
{% endhint %}

## Tenant Groups

The selector can also offer your [tenant groups](../../tenant/administration/tenants/groups/README.md), so you can view data for every tenant in a group at once. This is off by default: turn on **Tenant Groups in Tenant Selector** on the [features.md](../../cipp/settings/features.md "mention") settings tab to use it. While it is off, the selector offers single tenants and **\*All Tenants** only.

Selecting a group shows data for the tenants in that group that you have access to, on pages that support it. The page address carries a `tenantGroup` parameter in place of `tenantFilter`, so a link to a page keeps the group selected.

Not every page can show a group:

* A page that works across tenants but cannot show a group asks you to choose a tenant or **\*All Tenants** instead.
* A page that works on one tenant at a time asks you to choose a tenant, as it does under **\*All Tenants**.
* A page that does not use the selected tenant at all, such as settings and template pages, opens as normal.

Tenant groups are not offered when every custom role you hold has **Block tenant groups in the tenant selector** switched on. That setting only affects the selector: tenant groups can still be used to target standards, alerts and other settings. See [add.md](../../cipp/advanced/authentication/cipp-roles/add.md "mention").

## Tenant Not Available

When a link opens CIPP with a tenant in its address that you cannot access, or that CIPP does not manage, the page shows **Tenant not available** in place of its content, with a **Return to Home** button. A link to a tenant group you cannot access, or one that no longer exists, shows **Tenant group not available** in the same way. Pick a different tenant or group from the selector to carry on.

## On Narrow Screens

Where the window is too narrow for the selector, the menu bar shows the current tenant as a chip in its place. Selecting the chip opens a full-screen picker with its own search box and the same **All Tenants** entry, favourites, recent tenants, tenant groups and stars as the dropdown, so the same choices are available with more room to make them.

Both forms read the same favourites and recent tenants, so resizing the window, or opening CIPP on a phone in a browser you have already used, keeps the groups you are used to.

The tenant information flyout described below is not available from the picker. See [mobile-layout.md](../mobile-layout.md "mention").

## Tenant Information

The building icon to the left of the selector opens a flyout with details of the currently selected tenant, available from any page. It is unavailable while All Tenants is selected, and is not shown on narrow screens, where the selector is replaced by the tenant chip described above.

| Field                                    | Description                                                                     |
| ---------------------------------------- | ------------------------------------------------------------------------------- |
| Display Name                             | The tenant's display name.                                                      |
| ID                                       | The tenant's directory ID.                                                      |
| Street                                   | The street recorded on the tenant's address.                                    |
| Postal Code                              | The postal code recorded on the tenant's address.                               |
| Technical Notification Mails             | The technical contact addresses Microsoft uses for service notifications.       |
| On Premises Sync Enabled                 | Whether directory synchronisation from on-premises Active Directory is enabled. |
| On Premises Last Sync Date Time          | When the directory last synchronised.                                           |
| On Premises Last Password Sync Date Time | When passwords last synchronised.                                               |

## Portal Shortcuts

The same flyout lists shortcuts for jumping straight to the tenant's Microsoft portals, each opening with the selected tenant already in context.

| Action                | Description                                                                                    |
| --------------------- | ---------------------------------------------------------------------------------------------- |
| Manage Tenant         | Opens the tenant's settings within CIPP. See [edit.md](../../tenant/manage/edit.md "mention"). |
| M365 Admin Portal     | Microsoft 365 admin center.                                                                    |
| Exchange Portal       | Exchange admin center.                                                                         |
| Entra Portal          | Microsoft Entra admin center.                                                                  |
| Teams Portal          | Teams admin center.                                                                            |
| Azure Portal          | Azure portal.                                                                                  |
| Intune Portal         | Microsoft Intune admin center.                                                                 |
| SharePoint Portal     | SharePoint admin center.                                                                       |
| Security Portal       | Microsoft Defender portal.                                                                     |
| Purview Portal        | Microsoft Purview portal.                                                                      |
| Power Platform Portal | Power Platform admin center.                                                                   |
| Power BI Portal       | Power BI admin portal.                                                                         |

Every portal other than **Manage Tenant** can be hidden from this list using the **Portal Links Configuration** settings described in [user-settings.md](user-settings.md "mention"), so you can shorten it to the portals you actually use.

{% include "../../../../.gitbook/includes/feature-request.md" %}
