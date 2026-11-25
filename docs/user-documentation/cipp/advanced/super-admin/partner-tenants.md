# Partner Tenants

Partner Tenants lets one CIPP instance manage customer tenants that belong to more than one partner (CSP) tenant. Each customer tenant is managed through the partner tenant that owns it, so you can bring the customers of a second partner into the same tenant list without a second CIPP instance.

{% hint style="danger" %}
This is a pre-alpha feature. It is under active development, is not officially supported, and should not be enabled in production. Use it at your own risk.
{% endhint %}

{% hint style="info" %}
This page is behind the **Multiple Partner Tenants** feature flag, which is off by default. Turn it on from the [Features](../../settings/features.md) settings page before the page appears. Using the page also requires the `superadmin` role.
{% endhint %}

The partner tenant CIPP was set up with is always listed first and marked as primary. Any partner tenants you add are listed beneath it.

To manage a partner tenant itself as a tenant in CIPP, as well as its customers, set the [Tenant Mode](tenant-mode.md) to **Multi Tenant - Add Partner Tenant**. Until that mode is set, the page shows a reminder and **Tenant List Management** is greyed out.

## Action Buttons

### Add Partner Tenant

Opens a dialog with a **Connect Partner Tenant** button. Sign in with the CIPP service account of the partner tenant you want to add. Once it is connected, that partner's customer tenants appear in the tenant list after the next tenant refresh.

## Table Details

| Column             | Description                                                                                                  |
| ------------------ | ------------------------------------------------------------------------------------------------------------ |
| Display Name       | The name of the partner tenant.                                                                              |
| Default Domain Name | The partner tenant's default domain.                                                                        |
| Is Primary         | Whether this is the partner tenant CIPP was originally set up with.                                          |
| Managed            | Whether the partner tenant itself appears as a selectable tenant in the tenant list.                         |
| Tenant Count       | How many customer tenants are managed through this partner tenant. Direct tenants and excluded tenants are not counted. |
| Last Token Refresh | When CIPP last refreshed its sign-in for this partner tenant.                                                |

## Table Actions

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Tenant List Management</td><td>Chooses whether the partner tenant appears as a manageable tenant in the tenant list. Choose <strong>Managed - selectable as a tenant</strong> to add it, or <strong>Not managed - hidden from the tenant list</strong> to remove it. Its customer tenants are unaffected either way. Greyed out until the Tenant Mode is set to <strong>Multi Tenant - Add Partner Tenant</strong>.</td><td>false</td></tr><tr><td>Remove Partner Tenant</td><td>Removes the partner tenant and deletes the credentials CIPP holds for it. Its customer tenants can no longer be managed until the partner is added again. Turn on <strong>Also remove this partner's customer tenants from the tenant cache immediately</strong> to take them out of the tenant list straight away. Greyed out for the primary partner tenant.</td><td>false</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% include "../../../../../.gitbook/includes/feature-request.md" %}
