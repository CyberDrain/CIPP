---
title: Deploy Policy Expand
---

<details>

<summary>Deploy Policy</summary>

Opens a drawer that applies a saved policy template to one or more tenants.

| Field                              | Description                                                                                                                                                                                                                                                      |
| ---------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Select Tenants                     | The tenants to deploy to. Several can be selected, and the same template is applied to each.                                                                                                                                                                     |
| Please choose a template to apply. | The policy template to deploy, chosen from those saved in Policy Templates. **Refresh Templates** reloads the list if a template was added since the drawer was opened.                                                                                          |
| Assignment                         | Who the deployed policy is assigned to: Do Not Assign, Assign to All Users, Assign to All Devices, Assign to All Users and Devices, or Assign to Custom Group.                                                                                                   |
| Group(s)                           | Shown when Assign to Custom Group is chosen. With a single tenant selected this is a picker of that tenant's groups. With several tenants or All Tenants it is a text field taking group display names separated by commas, where `*` may be used as a wildcard. |
| Exclude group(s)                   | Shown for every option except Do Not Assign. The same picker or name field as above, for the groups to exclude.                                                                                                                                                  |
| Assignment Filter (Optional)       | An assignment filter from the tenant to narrow which devices the policy applies to.                                                                                                                                                                              |
| Assignment Filter Mode             | Whether the filter includes or excludes matching devices. Shown once a filter is chosen.                                                                                                                                                                         |

The template's configuration is displayed below the picker so it can be checked before deploying.

Group pickers are only offered for a single tenant because a group belongs to one tenant. Picking groups also removes the failure mode of the name field, where a mistyped or renamed exclude group silently matched nothing and the policy was assigned without the exclusion. Changing the tenant selection clears any picked groups.

{% hint style="info" %}
Where the template contains variables written as `%name%`, the drawer asks for a value for each one, per tenant, before it will deploy. `%tenantid%` and `%tenantdomain%` are filled in automatically for each selected tenant.
{% endhint %}

{% hint style="warning" %}
Deploying a template does not always create a new policy. CIPP first looks for a policy in the target tenant whose name exactly matches the template's, and where one is found it overwrites that policy in place. A new policy is only created where no match exists.

Because the match is on the name alone, a policy created by hand under the same name will be overwritten, and a deployed policy that has since been renamed in Intune will not be recognised, so the next deployment creates a duplicate alongside it. Where two policies share a name, the more recently modified one is the one overwritten.

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

{% hint style="info" %}
An Administrative Templates policy built on an imported ADMX file (for example a browser vendor's templates) can be deployed to any tenant where the same ADMX and ADML files have been imported. Intune gives an imported setting a different identifier in every tenant, so CIPP matches each setting by its name, category and class rather than by identifier. Where the ADMX has not been imported into a target tenant, the deployment stops and names the settings it could not find; import the files under Devices > Configuration > Import ADMX in that tenant, wait until they show as Available, and deploy again.
{% endhint %}

</details>
