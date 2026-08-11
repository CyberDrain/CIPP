# Partner Relationships

Cross-tenant access policies define how the tenant works with other Microsoft 365 organizations: which external organizations its users can collaborate with through B2B, how much trust is extended to their multi-factor authentication and device compliance claims, and which of them act as a service provider for the tenant. This page lists the organizations that have such a configuration, resolving each one's tenant ID to a readable organization name.

It is a useful place to spot cross-tenant trust that nobody remembers setting up, including relationships left behind by a previous provider.

## Table Details

| Column                          | Description                                                                                                                                                     |
| ------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Tenant                          | The tenant the relationship belongs to. Most useful with All Tenants selected, where rows from every tenant appear together.                                    |
| Tenant Info - Display Name      | The name of the partner organization, resolved from its tenant ID.                                                                                              |
| Is Service Provider             | Whether the partner is recorded as a service provider for this tenant, which is how a CSP or delegated administration partner appears.                          |
| Is In Multi Tenant Organization | Whether the partner is part of the same multi-tenant organization as this tenant.                                                                               |
| Tenant Info                     | The full result of the organization lookup. The cell is a button that opens it in a dialog, showing the partner's display name, default domain and tenant ID. |

Beyond those, each row is the Graph resource type `crossTenantAccessPolicyConfigurationPartner`, which also carries the inbound and outbound B2B settings, the inbound trust settings and the automatic consent settings for the relationship. For more information on the properties please see the [Graph documentation](https://learn.microsoft.com/en-us/graph/api/resources/crosstenantaccesspolicyconfigurationpartner?view=graph-rest-1.0#properties).

{% hint style="warning" %}
This table is view only. Cross-tenant access settings are changed in the Microsoft Entra admin center.
{% endhint %}

{% hint style="info" %}
The partner name is not stored in the policy itself. CIPP looks up each partner's tenant ID against Microsoft to resolve it, so a partner whose tenant cannot be resolved shows a blank name with its details still available in the Tenant Info column.
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
