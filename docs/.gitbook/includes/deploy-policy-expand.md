---
title: Deploy Policy Expand
---

<details>

<summary>Deploy Policy</summary>

Opens a drawer that applies a saved policy template to one or more tenants.

| Field                              | Description                                                                                                                                                             |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Select Tenants                     | The tenants to deploy to. Several can be selected, and the same template is applied to each.                                                                            |
| Please choose a template to apply. | The policy template to deploy, chosen from those saved in Policy Templates. **Refresh Templates** reloads the list if a template was added since the drawer was opened. |
| Assignment                         | Who the deployed policy is assigned to: Do not assign, Assign to all users, Assign to all devices, Assign to all users and devices, or Assign to Custom Group.          |
| Custom Group Names                 | Shown when Assign to Custom Group is chosen. Group display names separated by commas, where `*` may be used as a wildcard.                                              |
| Exclude Group Names                | Shown for every option except Do not assign. Group display names to exclude, again comma separated and accepting `*` as a wildcard.                                     |
| Assignment Filter (Optional)       | An assignment filter from the tenant to narrow which devices the policy applies to.                                                                                     |
| Assignment Filter Mode             | Whether the filter includes or excludes matching devices. Shown once a filter is chosen.                                                                                |

The template's configuration is displayed below the picker so it can be checked before deploying.

{% hint style="info" %}
Where the template contains variables written as `%name%`, the drawer asks for a value for each one, per tenant, before it will deploy. `%tenantid%` and `%tenantdomain%` are filled in automatically for each selected tenant.
{% endhint %}

{% hint style="warning" %}
Deploying a template does not always create a new policy. CIPP first looks for a policy in the target tenant whose name exactly matches the template's, and where one is found it overwrites that policy in place. A new policy is only created where no match exists.

Because the match is on the name alone, a policy created by hand under the same name will be overwritten, and a deployed policy that has since been renamed in Intune will not be recognized, so the next deployment creates a duplicate alongside it. Where two policies share a name, the more recently modified one is the one overwritten.

The assignment chosen here is added to the policy's existing assignments rather than replacing them.
{% endhint %}

{% hint style="danger" %}
What an overwrite does to settings the template does not mention depends on the policy type.

For Settings Catalog and Administrative Templates this means any change made directly in the Microsoft Intune admin center since the template was captured is lost on the next deployment.
{% endhint %}

| Policy type              | Settings not present in the template                                                          |
| ------------------------ | --------------------------------------------------------------------------------------------- |
| Settings Catalog         | Removed. The policy's settings become exactly what the template holds.                        |
| Administrative Templates | Removed. Every configured setting on the policy is cleared before the template's are applied. |
| All other types          | Left as they are. The template's settings are merged over the existing ones.                  |

</details>
