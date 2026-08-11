---
description: Centralized Tenant Management and Oversight
---

# Tenants

The Tenants page lists every tenant CIPP knows about and controls how CIPP connects to each one. From here you can exclude tenants from processing, refresh or reset the permissions CIPP holds in a tenant, re-authenticate a direct tenant whose credentials have lapsed, refresh cached data, and remove a tenant altogether. Tenants are reached either through a Partner Center GDAP relationship or added directly with their own service account, and the actions available on a row depend on which of the two applies.

## Table Details

| Column                     | Description                                                                    |
| -------------------------- | ------------------------------------------------------------------------------ |
| Display Name               | The name of the tenant.                                                        |
| Default Domain Name        | The tenant's default domain.                                                   |
| Delegated Privilege Status | How CIPP connects to the tenant, shown as either GDAP Tenant or Direct Tenant. |
| Excluded                   | Whether the tenant is excluded from CIPP processing.                           |
| Exclude Date               | The date the tenant was excluded.                                              |
| Exclude User               | The user who excluded the tenant.                                              |

Quick filters above the table narrow the list to Included tenants, Excluded tenants, Direct tenants, or GDAP tenants. Selecting a row opens a flyout with further detail, including, for a direct tenant, the service account CIPP authenticates as and when it last authenticated.

## Table Actions

Several actions apply only to one kind of tenant, and none of them apply to your own partner tenant.

<table><thead><tr><th>Action</th><th>Description</th><th data-type="checkbox">Bulk Action Available</th></tr></thead><tbody><tr><td>Exclude Tenants</td><td>Excludes the selected tenant so CIPP no longer processes it. Not available for the partner tenant.</td><td>true</td></tr><tr><td>Include Tenants</td><td>Removes the exclusion from the selected tenant so CIPP processes it again. Not available for the partner tenant.</td><td>true</td></tr><tr><td>Refresh CPV Permissions</td><td>Re-applies CIPP's permissions in the selected tenant. Available for GDAP tenants only.</td><td>true</td></tr><tr><td>Re-authenticate Connection</td><td>Opens the onboarding wizard to sign in again and restore CIPP's connection to the tenant. Available for direct tenants only and used when the stored credentials have expired or been revoked.</td><td>true</td></tr><tr><td>Reset CPV Permissions</td><td>Deletes CIPP's service principal in the selected tenant and adds it back, then re-applies permissions. Available for GDAP tenants only.</td><td>true</td></tr><tr><td>Remove Tenant</td><td>Removes the tenant from CIPP. A direct tenant removed this way stays inaccessible until it is added again through the Setup Wizard.</td><td>true</td></tr><tr><td>Refresh CIPPDB Cache</td><td>Refreshes cached data for the selected tenant. You choose which cache type to refresh from a list.</td><td>true</td></tr><tr><td>Trace GDAP</td><td>Opens a trace showing how CIPP's access to the tenant is granted through its GDAP relationship. Available for GDAP tenants only.</td><td>true</td></tr><tr><td>More Info</td><td>Opens the Extended Info flyout with the full details for the selected row.</td><td>false</td></tr></tbody></table>

{% hint style="info" %}
## Force Refresh

The **Force Refresh** button above the table re-reads tenant details and updates the list. Enter a default domain name or tenant ID to refresh a single tenant, or leave the field empty to refresh them all. This is also the way to make a tenant that is missing from the list reappear.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
