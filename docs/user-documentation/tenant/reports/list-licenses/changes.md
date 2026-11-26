# Changes

The Licence Changes tab lists every licence added to or removed from a user in the last 30 days, with the date and who made the change. Use it to see what was assigned during a month, to check a licence invoice against what actually changed, or to find out who removed a licence from a user.

The changes are read from the tenant's Entra audit log. Each licence is its own row, so assigning three licences to a user in one go shows three rows. Only changes that succeeded are listed.

{% hint style="info" %}
The report needs Entra ID P1 or higher in the tenant, which Microsoft 365 Business Premium includes. Tenants without it may show fewer days or no changes at all, and are not collected for the cached and All Tenants views.
{% endhint %}

## Live and Cached Data

The tab opens with live data for the selected tenant. Select the **Live** chip to switch to cached data from the CIPP reporting database, and **Sync** to refresh the cache for the tenant. The All Tenants view always uses cached data and only lists tenants whose cache has been collected.

## Table Details

| Column              | Description                                                                                                                                                                             |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant              | The tenant the change was made in. Shown in the All Tenants view.                                                                                                                       |
| Activity Date Time  | When the licence was added or removed.                                                                                                                                                  |
| User Principal Name | The user whose licences changed.                                                                                                                                                        |
| Change              | **Added** or **Removed**.                                                                                                                                                               |
| License             | The friendly name of the licence, or its SKU name where Microsoft publishes no friendly name.                                                                                           |
| Initiated By        | Who made the change: the user's sign-in name, or the name of the application. A licence that comes from a group shows **Microsoft Azure AD Group-Based Licensing**.                     |
| Initiated By Type   | **User** when a person made the change, **Application** when an app or service did.                                                                                                     |
| Cache Timestamp     | When the row was last collected. Shown for cached data.                                                                                                                                 |

The Extended Info flyout also shows the licence's SKU name and SKU ID.

{% hint style="info" %}
Changes made by your own technicians through partner access show the technician's sign-in name from your partner tenant. Changes made through CIPP show the CIPP service account.
{% endhint %}

Changing which service plans are switched on inside a licence a user already holds is not listed, since no licence was added or removed.

{% include "../../../../../.gitbook/includes/feature-request.md" %}
