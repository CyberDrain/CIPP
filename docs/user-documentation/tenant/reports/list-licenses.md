# License Report

This report lists every license SKU present in the selected tenant, showing how many of each are owned, how many are in use, and who holds them. It is the quickest way to spot over-provisioning across a client base, or to find which users and groups are consuming a particular SKU.

The report supports the All Tenants view. Because gathering license data from every tenant takes time, the first request queues a background job and shows a message asking you to check back once it completes. Results are cached for an hour, so subsequent loads return immediately.

## Table Details

| Column          | Description                                                                                            |
| --------------- | ------------------------------------------------------------------------------------------------------ |
| Tenant          | The tenant the licenses belong to. Most useful in the All Tenants view.                                |
| License         | The friendly name of the SKU, resolved from Microsoft's published product names.                       |
| Count Used      | The number of licenses currently assigned.                                                             |
| Count Available | The number of licenses owned but not yet assigned.                                                     |
| Total Licenses  | The total number of licenses owned.                                                                    |
| Assigned Users  | The users holding this license, including whether each assignment is direct or inherited from a group. |
| Assigned Groups | The groups this license is assigned to, for group-based licensing.                                     |
| Term Info       | Subscription detail for the SKU. See below.                                                            |

{% hint style="info" %}
SKUs configured as excluded in CIPP's license settings are omitted from the report.
{% endhint %}

### Term Info

A SKU can be backed by more than one subscription, so Term Info holds an entry per subscription.

{% hint style="warning" %}
This report tries to make an estimate of the NCE term by calculating the dates. As this is an estimate, these dates might not be accurate and require manual checking in your CSP's own environment.
{% endhint %}

| Property            | Description                                                                                                      |
| ------------------- | ---------------------------------------------------------------------------------------------------------------- |
| Status              | The subscription's current status, for example enabled or warning.                                               |
| Total Licenses      | The number of licenses on this subscription.                                                                     |
| Days Until Renew    | How many days remain before the next lifecycle date.                                                             |
| Next Lifecycle      | The date the subscription next renews or expires, as reported by the tenant's directory rather than by your CSP. |
| Created Date Time   | When the subscription was created.                                                                               |
| Is Trial            | Whether the subscription is a trial.                                                                             |
| Subscription Id     | The Graph subscription identifier.                                                                               |
| CSP Subscription Id | The commerce subscription identifier, for matching against your CSP portal.                                      |
| OCP Subscription Id | The partner center subscription identifier.                                                                      |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Assign License to User</td><td>Assigns the selected license to a user in that row's tenant. The user list is drawn from the tenant the row belongs to.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
This page accepts filters passed in the URL, so links from dashboards and other reports can open it pre-filtered to a particular SKU or tenant.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
