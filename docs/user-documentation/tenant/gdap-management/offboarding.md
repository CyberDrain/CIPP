# Offboarding

This page offboards a tenant, removing the delegated access and applications you hold over it. Select the tenant, choose the actions to perform, and submit.

{% hint style="danger" %}
Once an offboarding has been executed, it cannot be undone.
{% endhint %}

Selecting a tenant shows a summary of what you currently hold against it, so you can judge the scope before choosing any actions. Each figure other than the CSP contract can be expanded to list the underlying items.

| Statistic           | Description                                                                              |
| ------------------- | ---------------------------------------------------------------------------------------- |
| GDAP Relationships  | The number of delegated admin relationships between your partner tenant and this tenant. |
| CSP Contract        | Whether a reseller contract relationship exists with this tenant.                        |
| MSP Applications    | The number of applications in the tenant that originate from your partner tenant.        |
| Vendor Applications | The number of applications in the tenant that originate from a known third-party vendor. |

## Offboarding actions to perform

The tenant will not be fully offboarded unless all the relationships and contracts are terminated. Options with nothing to act on are disabled, so a greyed-out switch means CIPP found nothing of that kind in the tenant.

| Setting                                                                                                          | Description                                                                       |
| ---------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------- |
| Vendor Applications to Remove                                                                                    | The third-party vendor applications to remove from the tenant.                    |
| Remove all guest users originating from the CSP tenant.                                                          | Removes guest accounts in the customer tenant that came from your partner tenant. |
| Remove all notification contacts originating from the CSP tenant (technical, security, marketing notifications). | Clears your partner tenant's addresses from the customer's notification contacts. |
| Remove all Domain Analyzer results for this tenant.                                                              | Deletes the tenant's stored Domain Analyzer data from CIPP.                       |

{% hint style="danger" %}
The following actions will terminate all delegated access to the customer tenant!
{% endhint %}

| Setting                                                                                  | Description                                                                                                                                                                                                           |
| ---------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Remove all multitenant applications originating from CSP tenant (including CIPP-SAM).    | Removes your multitenant applications from the customer tenant, including the application CIPP itself authenticates with.                                                                                             |
| Terminate all active GDAP relationships (will send email to tenant admins and contacts). | Ends every active relationship between your partner tenant and the customer. This can only terminate relationships with your partner tenant. Any other service providers will have to manage their own relationships. |
| Terminate contract relationship (reseller, etc).                                         | Ends the reseller or other contract relationship with the customer.                                                                                                                                                   |

{% hint style="warning" %}
Selecting **Terminate all active GDAP relationships** also removes the tenant from CIPP's tenant list as part of the same run. The other options leave the tenant in place, so if you need it gone without terminating relationships, use the **Delete Tenant** action on [tenants.md](../../cipp/settings/tenants.md "mention").
{% endhint %}

{% include "../../../../.gitbook/includes/feature-request.md" %}
